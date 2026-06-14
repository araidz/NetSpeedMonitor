import SwiftUI
import ServiceManagement
import SystemConfiguration

enum NetSpeedUpdateInterval: Int, CaseIterable, Identifiable {
    case Sec1 = 1
    case Sec2 = 2
    case Sec5 = 5
    case Sec10 = 10
    case Sec30 = 30

    var id: Int { self.rawValue }

    var displayName: String {
        switch self {
        case .Sec1: return "1s"
        case .Sec2: return "2s"
        case .Sec5: return "5s"
        case .Sec10: return "10s"
        case .Sec30: return "30s"
        }
    }
}

@MainActor
@Observable
final class MenuBarState {

    // MARK: - Persisted settings

    /// Keys used to persist settings in `UserDefaults`.
    private enum DefaultsKey {
        static let autoLaunch = "AutoLaunchEnabled"
        static let updateInterval = "NetSpeedUpdateInterval"
    }

    var autoLaunchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoLaunchEnabled, forKey: DefaultsKey.autoLaunch)
            updateAutoLaunchStatus()
        }
    }

    var netSpeedUpdateInterval: NetSpeedUpdateInterval {
        didSet {
            UserDefaults.standard.set(netSpeedUpdateInterval.rawValue, forKey: DefaultsKey.updateInterval)
            logger.info("netSpeedUpdateInterval, \(self.netSpeedUpdateInterval.displayName)")
            restartMonitoring()
        }
    }

    // MARK: - Live readings (always expressed in MB/s)

    private(set) var uploadSpeedMBps: Double = 0.0
    private(set) var downloadSpeedMBps: Double = 0.0

    /// The menu bar icon, rendered from the current speeds.
    var currentIcon: NSImage {
        MenuBarIconGenerator.generateIcon(uploadMBps: uploadSpeedMBps, downloadMBps: downloadSpeedMBps)
    }

    // MARK: - Internal monitoring state

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var primaryInterface: String?
    @ObservationIgnored private let netTrafficStat = NetTrafficStatReceiver()

    private static let bytesPerMB = 1024.0 * 1024.0

    // MARK: - Lifecycle

    init() {
        // Restore persisted settings. (didSet observers do not fire for these
        // initial assignments inside the initializer.)
        autoLaunchEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.autoLaunch)
        let storedInterval = UserDefaults.standard.integer(forKey: DefaultsKey.updateInterval)
        netSpeedUpdateInterval = NetSpeedUpdateInterval(rawValue: storedInterval) ?? .Sec1

        // Reflect the real login-item state rather than our stored guess.
        autoLaunchEnabled = currentAutoLaunchStatus()

        startMonitoring()
    }

    deinit {
        monitorTask?.cancel()
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
            logger.info("updateAutoLaunchStatus succeeded, autoLaunchEnabled: \(String(self.autoLaunchEnabled)), service.enabled: \(String(service.status == .enabled))")
        } catch {
            logger.warning("updateAutoLaunchStatus failed: \(error.localizedDescription), autoLaunchEnabled: \(String(self.autoLaunchEnabled)), service.enabled: \(String(service.status == .enabled))")
            autoLaunchEnabled = currentAutoLaunchStatus()
        }
    }

    // MARK: - Monitoring loop

    private func findPrimaryInterface() -> String? {
        let storeRef = SCDynamicStoreCreate(nil, "FindCurrentInterfaceIpMac" as CFString, nil, nil)
        let global = SCDynamicStoreCopyValue(storeRef, "State:/Network/Global/IPv4" as CFString)
        return global?.value(forKey: "PrimaryInterface") as? String
    }

    /// Takes a single traffic sample and updates the published speeds (in MB/s).
    private func sample() {
        primaryInterface = findPrimaryInterface()
        guard let primaryInterface else { return }

        guard let statMap = netTrafficStat.getNetTrafficStatMap(),
              let stat = statMap.object(forKey: primaryInterface) as? NetTrafficStatOC else {
            return
        }

        downloadSpeedMBps = stat.ibytes_per_sec.doubleValue / Self.bytesPerMB
        uploadSpeedMBps = stat.obytes_per_sec.doubleValue / Self.bytesPerMB

        logger.info("deltaIn: \(String(format: "%.4f", self.downloadSpeedMBps)) MB/s, deltaOut: \(String(format: "%.4f", self.uploadSpeedMBps)) MB/s")
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.sample()
                try? await Task.sleep(for: .seconds(self.netSpeedUpdateInterval.rawValue))
            }
        }
        logger.info("startMonitoring")
    }

    private func restartMonitoring() {
        logger.info("restartMonitoring")
        startMonitoring()
    }
}
