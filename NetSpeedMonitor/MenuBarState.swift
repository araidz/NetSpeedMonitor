import SwiftUI
import ServiceManagement
import os.log

let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NetSpeedMonitor", category: "monitor")

@MainActor
@Observable
final class MenuBarState {

    // MARK: - Persisted settings

    /// Key used to persist the launch-at-login preference in `UserDefaults`.
    private static let autoLaunchKey = "AutoLaunchEnabled"
    /// Key used to persist the chosen sampling interval.
    private static let updateIntervalKey = "UpdateIntervalSeconds"

    /// Sampling intervals offered in the menu, in seconds.
    static let intervalOptions: [Double] = [0.5, 1.0, 2.0, 5.0]

    var autoLaunchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoLaunchEnabled, forKey: Self.autoLaunchKey)
            updateAutoLaunchStatus()
        }
    }

    /// How often the readout refreshes, in seconds. A change takes effect after
    /// the current sleep completes (at most the prior interval, currently 5s).
    var updateInterval: Double {
        didSet {
            guard updateInterval != oldValue else { return }
            UserDefaults.standard.set(updateInterval, forKey: Self.updateIntervalKey)
        }
    }

    // MARK: - Live readings (always expressed in MB/s)

    private(set) var uploadSpeedMBps: Double = 0.0
    private(set) var downloadSpeedMBps: Double = 0.0

    // MARK: - Session totals (bytes since launch or last reset)

    private(set) var sessionDownloadBytes: Int64 = 0
    private(set) var sessionUploadBytes: Int64 = 0

    // MARK: - Speed test (on-demand, via networkQuality)

    private(set) var speedTest: SpeedTestResult?
    // Guards against launching a second test while one is in flight.
    @ObservationIgnored private(set) var speedTestRunning = false
    // When set, the readout renders in this colour instead of its speed band —
    // used to flash on test completion.
    @ObservationIgnored private var flashColor: NSColor?

    /// The menu bar icon, rendered for the status button's appearance.
    func icon(for appearance: NSAppearance) -> NSImage {
        MenuBarIconGenerator.generateIcon(
            uploadMBps: uploadSpeedMBps, downloadMBps: downloadSpeedMBps,
            appearance: appearance, tint: flashColor)
    }

    /// Invoked on the main actor after every sample so the status item can
    /// redraw its icon. The menu is rebuilt lazily on open, so it is not
    /// driven from here.
    var onUpdate: (@MainActor () -> Void)?

    // MARK: - Internal monitoring state

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private let sampler = NetSampler()
    @ObservationIgnored private var sessionGeneration: UInt = 0

    // MARK: - Lifecycle

    init() {
        // Restore persisted settings. (didSet observers do not fire for
        // assignments made inside the initializer.)
        autoLaunchEnabled = UserDefaults.standard.bool(forKey: Self.autoLaunchKey)

        let storedInterval = UserDefaults.standard.double(forKey: Self.updateIntervalKey)
        updateInterval = storedInterval > 0 ? storedInterval : 1.0

        // Reflect the real login-item state rather than our stored guess.
        autoLaunchEnabled = currentAutoLaunchStatus()

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
    }

    // MARK: - Speed test

    /// Runs one networkQuality test (~15s) off the main actor and stores the
    /// result. The menu reads `speedTestRunning`/`speedTest` on next open.
    func runSpeedTest() {
        guard !speedTestRunning else { return }
        speedTestRunning = true
        Task {
            defer { speedTestRunning = false }
            do {
                speedTest = try await SpeedTest.run()
                await flashReadout()
            } catch {
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

    private func currentAutoLaunchStatus() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func updateAutoLaunchStatus() {
        let service = SMAppService.mainApp
        do {
            if autoLaunchEnabled {
                if service.status == .notFound || service.status == .notRegistered {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            logger.warning("updateAutoLaunchStatus failed: \(error.localizedDescription, privacy: .public)")
            autoLaunchEnabled = currentAutoLaunchStatus()
        }
    }

    // MARK: - Monitoring loop

    /// Applies one off-main reading on the main actor and redraws the icon.
    private func apply(_ reading: NetReading) {
        downloadSpeedMBps = reading.downloadMBps
        uploadSpeedMBps = reading.uploadMBps
        if reading.generation == sessionGeneration {
            sessionDownloadBytes += reading.deltaDownBytes
            sessionUploadBytes += reading.deltaUpBytes
        }
        onUpdate?()
    }

    private func startMonitoring() {
        monitorTask = Task.detached(priority: .utility) { [weak self, sampler = self.sampler] in
            while true {
                let reading = sampler.reading()
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.apply(reading)
                }
                guard let interval = await MainActor.run(body: { [weak self] in self?.updateInterval }) else {
                    return
                }
                // A 10% tolerance allows macOS to coalesce periodic wakeups.
                do {
                    try await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval * 0.1))
                } catch {
                    return
                }
            }
        }
    }
}
