import SwiftUI
import ServiceManagement
import SystemConfiguration
import os.log

public let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "elegracer")

@MainActor
@Observable
final class MenuBarState {

    // MARK: - Persisted settings

    /// Key used to persist the launch-at-login preference in `UserDefaults`.
    private static let autoLaunchKey = "AutoLaunchEnabled"

    /// Fixed sampling interval, in seconds.
    private static let updateIntervalSeconds = 1

    var autoLaunchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoLaunchEnabled, forKey: Self.autoLaunchKey)
            updateAutoLaunchStatus()
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
        // Restore persisted setting. (didSet observers do not fire for these
        // initial assignments inside the initializer.)
        autoLaunchEnabled = UserDefaults.standard.bool(forKey: Self.autoLaunchKey)

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

    /// Takes a single traffic sample and updates the speeds (in MB/s).
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
                try? await Task.sleep(for: .seconds(Self.updateIntervalSeconds))
            }
        }
        logger.info("startMonitoring")
    }
}
