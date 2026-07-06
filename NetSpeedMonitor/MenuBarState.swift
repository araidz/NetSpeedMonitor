import SwiftUI
import ServiceManagement
import SystemConfiguration
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

    /// How often the readout refreshes, in seconds. Changing it restarts the loop.
    var updateInterval: Double {
        didSet {
            guard updateInterval != oldValue else { return }
            UserDefaults.standard.set(updateInterval, forKey: Self.updateIntervalKey)
            startMonitoring()
        }
    }

    // MARK: - Live readings (always expressed in MB/s)

    private(set) var uploadSpeedMBps: Double = 0.0
    private(set) var downloadSpeedMBps: Double = 0.0

    // MARK: - Session totals (bytes since launch or last reset)

    private(set) var sessionDownloadBytes: Int64 = 0
    private(set) var sessionUploadBytes: Int64 = 0

    /// The menu bar icon, rendered from the current speeds.
    var currentIcon: NSImage {
        MenuBarIconGenerator.generateIcon(uploadMBps: uploadSpeedMBps, downloadMBps: downloadSpeedMBps)
    }

    /// Invoked on the main actor after every sample so the status item can
    /// redraw its icon. The menu is rebuilt lazily on open, so it is not
    /// driven from here.
    var onUpdate: (@MainActor () -> Void)?

    // MARK: - Internal monitoring state

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var primaryInterface: String?
    @ObservationIgnored private let netTrafficStat = NetTrafficStatReceiver()
    // Created once; each primary-interface query reuses this store handle.
    @ObservationIgnored private lazy var dynamicStore: SCDynamicStore? =
        SCDynamicStoreCreate(nil, "NetSpeedMonitor" as CFString, nil, nil)

    private static let bytesPerMB = 1024.0 * 1024.0

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
        sessionDownloadBytes = 0
        sessionUploadBytes = 0
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

    private func findPrimaryInterface() -> String? {
        let global = SCDynamicStoreCopyValue(dynamicStore, "State:/Network/Global/IPv4" as CFString)
        return global?.value(forKey: "PrimaryInterface") as? String
    }

    /// Takes a single traffic sample and updates the speeds (in MB/s).
    private func sample() {
        primaryInterface = findPrimaryInterface()

        guard let primaryInterface,
              let statMap = netTrafficStat.getNetTrafficStatMap(),
              let stat = statMap.object(forKey: primaryInterface) as? NetTrafficStatOC else {
            // No active interface (e.g. offline): show zero, not a stale value.
            downloadSpeedMBps = 0.0
            uploadSpeedMBps = 0.0
            return
        }

        downloadSpeedMBps = stat.ibytes_per_sec.doubleValue / Self.bytesPerMB
        uploadSpeedMBps = stat.obytes_per_sec.doubleValue / Self.bytesPerMB

        sessionDownloadBytes += Int64(stat.delta_ibytes)
        sessionUploadBytes += Int64(stat.delta_obytes)
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.sample()
                self.onUpdate?()
                try? await Task.sleep(for: .seconds(self.updateInterval))
            }
        }
    }
}
