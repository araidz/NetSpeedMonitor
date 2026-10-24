import SwiftUI
import ServiceManagement
import os.log

let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NetSpeedMonitor", category: "monitor")

@MainActor
@Observable
final class MenuBarState {

    // MARK: - Persisted settings

    private static let updateIntervalKey = "UpdateIntervalSeconds"
    private static let rateUnitKey = "RateUnit"
    private static let autoScaleKey = "AutoScaleSmallRates"
    private static let pinnedInterfaceKey = "PinnedInterface"
    private static let sessionDownloadKey = "SessionDownloadBytes"
    private static let sessionUploadKey = "SessionUploadBytes"

    /// Sampling intervals offered in the menu, in seconds.
    static let intervalOptions: [Double] = [0.5, 1.0, 2.0, 5.0]
    /// Samples kept for the menu's history graph.
    static let historyCapacity = 60

    /// Mirrors the system login-item state; change it via `setAutoLaunch`.
    private(set) var autoLaunchEnabled: Bool

    /// How often the readout refreshes, in seconds. Takes effect immediately.
    var updateInterval: Double {
        didSet {
            guard updateInterval != oldValue else { return }
            UserDefaults.standard.set(updateInterval, forKey: Self.updateIntervalKey)
            // History is kept: the graph plots samples by age, so it keeps
            // drawing through the switch instead of blanking for an interval.
            restartMonitoring()
        }
    }

    var rateUnit: RateUnit {
        didSet {
            UserDefaults.standard.set(rateUnit.rawValue, forKey: Self.rateUnitKey)
            onUpdate?()
        }
    }

    var autoScale: Bool {
        didSet {
            UserDefaults.standard.set(autoScale, forKey: Self.autoScaleKey)
            onUpdate?()
        }
    }

    var format: RateFormat { RateFormat(unit: rateUnit, autoScale: autoScale) }

    /// Interface to measure; nil follows the system's primary interface.
    var pinnedInterface: String? {
        didSet {
            guard pinnedInterface != oldValue else { return }
            UserDefaults.standard.set(pinnedInterface, forKey: Self.pinnedInterfaceKey)
            history.removeAll()
            restartMonitoring()
        }
    }

    // MARK: - Live readings (bytes/sec)

    private(set) var uploadRate: Double = 0.0
    private(set) var downloadRate: Double = 0.0
    /// The interface the last sample came from; nil when offline.
    private(set) var currentInterface: String?

    struct Sample { let down: Double; let up: Double; let at: Date }
    /// Most recent samples, oldest first, at most `historyCapacity`.
    private(set) var history: [Sample] = []

    // MARK: - Session totals (bytes since the last reset; survive relaunches)

    private(set) var sessionDownloadBytes: Int64 = 0
    private(set) var sessionUploadBytes: Int64 = 0
    @ObservationIgnored private var lastSessionSave = Date()

    // MARK: - Speed test (on-demand, via networkQuality)

    private(set) var speedTest: SpeedTestResult?
    private(set) var speedTestError: String?
    // Guards against launching a second test while one is in flight.
    @ObservationIgnored private(set) var speedTestRunning = false
    // When set, the readout renders in this colour instead of its speed band —
    // used to flash on test completion.
    @ObservationIgnored private var flashColor: NSColor?

    /// The menu bar icon, rendered for the status button's appearance.
    func icon(for appearance: NSAppearance) -> NSImage {
        MenuBarIconGenerator.generateIcon(
            upload: uploadRate, download: downloadRate, format: format,
            appearance: appearance, tint: flashColor)
    }

    /// Invoked on the main actor whenever the readout should redraw. The menu
    /// is rebuilt lazily on open, so it is not driven from here.
    var onUpdate: (@MainActor () -> Void)?

    // MARK: - Internal monitoring state

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private let sampler = NetSampler()
    @ObservationIgnored private var sessionGeneration: UInt = 0

    // MARK: - Lifecycle

    init() {
        let defaults = UserDefaults.standard
        let storedInterval = defaults.double(forKey: Self.updateIntervalKey)
        updateInterval = storedInterval > 0 ? storedInterval : 1.0
        rateUnit = defaults.string(forKey: Self.rateUnitKey).flatMap(RateUnit.init) ?? .megabytes
        autoScale = defaults.bool(forKey: Self.autoScaleKey)
        pinnedInterface = defaults.string(forKey: Self.pinnedInterfaceKey)
        autoLaunchEnabled = SMAppService.mainApp.status == .enabled
        sessionDownloadBytes = Int64(defaults.integer(forKey: Self.sessionDownloadKey))
        sessionUploadBytes = Int64(defaults.integer(forKey: Self.sessionUploadKey))

        // Nobody can see the readout while the displays sleep, so stop waking
        // up to sample. Traffic in the gap still lands in the session totals.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopMonitoring() }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startMonitoring() }
        }

        startMonitoring()
    }

    deinit {
        monitorTask?.cancel()
    }

    // MARK: - Session totals

    func resetSessionTotals() {
        sessionGeneration = sampler.resetBaseline()
        sessionDownloadBytes = 0
        sessionUploadBytes = 0
        saveSessionTotals()
    }

    /// Called on quit and at most once a minute while sampling, so a crash or
    /// power loss costs at most a minute of totals.
    func saveSessionTotals() {
        let defaults = UserDefaults.standard
        defaults.set(sessionDownloadBytes, forKey: Self.sessionDownloadKey)
        defaults.set(sessionUploadBytes, forKey: Self.sessionUploadKey)
        lastSessionSave = Date()
    }

    // MARK: - Speed test

    /// Runs one networkQuality test (~15s) off the main actor and stores the
    /// result or error. The menu reads them on next open.
    func runSpeedTest() {
        guard !speedTestRunning else { return }
        speedTestRunning = true
        speedTestError = nil
        Task {
            defer { speedTestRunning = false }
            do {
                speedTest = try await SpeedTest.run()
                await flashReadout()
            } catch {
                speedTestError = error.localizedDescription
                logger.warning("speed test failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Blinks the menu-bar readout in the system accent colour a few times so a
    /// finished test is noticeable even when the menu is closed. Drives the icon
    /// directly via `onUpdate`, so it is independent of the sampling interval.
    private func flashReadout() async {
        for _ in 0..<3 {
            flashColor = .controlAccentColor; onUpdate?()
            try? await Task.sleep(for: .milliseconds(180))
            flashColor = nil; onUpdate?()
            try? await Task.sleep(for: .milliseconds(180))
        }
    }

    // MARK: - Auto launch

    func setAutoLaunch(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            logger.warning("setAutoLaunch failed: \(error.localizedDescription, privacy: .public)")
        }
        // The user may have to allow it in System Settings first.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        autoLaunchEnabled = service.status == .enabled
    }

    // MARK: - Monitoring loop

    /// Applies one off-main reading on the main actor and redraws the icon.
    private func apply(_ reading: NetReading) {
        downloadRate = reading.downBytesPerSec
        uploadRate = reading.upBytesPerSec
        currentInterface = reading.interface
        if reading.generation == sessionGeneration {
            sessionDownloadBytes += reading.deltaDownBytes
            sessionUploadBytes += reading.deltaUpBytes
            if Date().timeIntervalSince(lastSessionSave) > 60 { saveSessionTotals() }
        }
        history.append(Sample(down: reading.downBytesPerSec, up: reading.upBytesPerSec, at: Date()))
        if history.count > Self.historyCapacity {
            history.removeFirst(history.count - Self.historyCapacity)
        }
        onUpdate?()
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task.detached(priority: .utility) { [weak self, sampler = self.sampler] in
            while true {
                guard let settings = await MainActor.run(body: { [weak self] in
                    self.map { ($0.pinnedInterface, $0.updateInterval) }
                }) else { return }
                let reading = sampler.reading(interface: settings.0)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.apply(reading)
                }
                // A 10% tolerance allows macOS to coalesce periodic wakeups.
                do {
                    try await Task.sleep(for: .seconds(settings.1), tolerance: .seconds(settings.1 * 0.1))
                } catch {
                    return
                }
            }
        }
    }

    private func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Applies a settings change now instead of after the current sleep —
    /// unless sampling is paused for display sleep.
    private func restartMonitoring() {
        guard monitorTask != nil else { return }
        startMonitoring()
    }
}
