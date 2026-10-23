import SwiftUI
import AppKit

@main
struct NetSpeedMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar-only app (LSUIElement); no window scene is shown.
        Settings { EmptyView() }
    }
}

/// Owns the status item and its menu. Using AppKit directly (instead of
/// SwiftUI's `MenuBarExtra`) is deliberate: `MenuBarExtra(.menu)` gives no
/// "menu opened" event and live-rebuilds the menu whenever observed state
/// changes, which collapsed the Update Interval submenu every second. An
/// `NSMenu` is rebuilt in `menuNeedsUpdate` — right before it shows — so the
/// session stats are a snapshot from the moment the icon is clicked and stay
/// put until the menu is reopened.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let state = MenuBarState()
    private var statusItem: NSStatusItem!
    private var appearanceObservation: NSKeyValueObservation?
    /// The Top Apps submenu of the current menu; sampled each time it opens.
    private weak var appsMenu: NSMenu?
    private var appsTask: Task<Void, Never>?

    private static let topAppsLimit = 8

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        state.onUpdate = { [weak self] in self?.refreshIcon() }
        // Redraw on light/dark switches instead of waiting for the next sample.
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
        refreshIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.saveSessionTotals()
    }

    /// The menu-bar number keeps ticking live even while the menu is open.
    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        button.image = state.icon(for: button.effectiveAppearance)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === appsMenu {
            sampleTopApps(into: menu)
        } else {
            rebuild(menu)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === appsMenu { appsTask?.cancel() }
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        let format = state.format

        if state.history.count > 1 {
            let span = Duration.seconds(Double(MenuBarState.historyCapacity) * state.updateInterval)
                .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
            let graph = NSMenuItem()
            graph.view = HistoryGraphView(samples: state.history, capacity: MenuBarState.historyCapacity,
                                          span: span, format: format)
            menu.addItem(graph)
            menu.addItem(.separator())
        }

        let down = state.sessionDownloadBytes.formatted(.byteCount(style: .binary))
        let up = state.sessionUploadBytes.formatted(.byteCount(style: .binary))
        menu.addItem(readOnly("↓ \(down) received"))
        menu.addItem(readOnly("↑ \(up) sent"))
        menu.addItem(action("Reset Session Totals", #selector(resetTotals)))

        let apps = NSMenu()
        apps.delegate = self
        appsMenu = apps
        let appsItem = NSMenuItem(title: "Top Apps", action: nil, keyEquivalent: "")
        appsItem.submenu = apps
        menu.addItem(appsItem)

        menu.addItem(.separator())
        if let result = state.speedTest {
            menu.addItem(readOnly("↓ \(format.full(result.downloadBytesPerSec))   ↑ \(format.full(result.uploadBytesPerSec))"))
            menu.addItem(readOnly(String(format: "Responsiveness  %.0f RPM", result.responsiveness)))
        }
        if let error = state.speedTestError {
            let item = readOnly("Speed test failed: \(error.prefix(60))")
            item.toolTip = error
            menu.addItem(item)
        }
        if state.speedTestRunning {
            menu.addItem(readOnly("Testing…"))
        } else {
            menu.addItem(action("Run Speed Test", #selector(runSpeedTest)))
        }

        menu.addItem(.separator())
        menu.addItem(intervalMenu())
        menu.addItem(unitsMenu())
        menu.addItem(interfaceMenu())

        let login = action("Launch at Login", #selector(toggleLogin))
        login.state = state.autoLaunchEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(readOnly("NetSpeedMonitor \(Self.appVersion)"))
        menu.addItem(action("Quit", #selector(quit)))
    }

    // MARK: - Submenus

    private func intervalMenu() -> NSMenuItem {
        submenu("Update Interval", MenuBarState.intervalOptions.map { seconds in
            let item = action(Self.intervalLabel(seconds), #selector(setInterval(_:)))
            item.representedObject = seconds
            item.state = seconds == state.updateInterval ? .on : .off
            return item
        })
    }

    private func unitsMenu() -> NSMenuItem {
        var items = RateUnit.allCases.map { unit in
            let item = action(unit.title, #selector(setUnit(_:)))
            item.representedObject = unit.rawValue
            item.state = unit == state.rateUnit ? .on : .off
            return item
        }
        let scale = action("Show Slow Speeds in K", #selector(toggleAutoScale))
        scale.state = state.autoScale ? .on : .off
        items += [.separator(), scale]
        return submenu("Units", items)
    }

    private func interfaceMenu() -> NSMenuItem {
        let labels = Interfaces.displayNames()
        func label(_ bsd: String) -> String { labels[bsd] ?? bsd }

        let pinned = state.pinnedInterface
        var title = "Automatic"
        if pinned == nil, let current = state.currentInterface { title += " — \(label(current))" }
        let automatic = action(title, #selector(setInterface(_:)))
        automatic.state = pinned == nil ? .on : .off

        var names = Interfaces.active()
        if let pinned, !names.contains(pinned) { names.append(pinned) } // keep the checkmark visible
        let choices = names.map { name in
            let item = action(label(name), #selector(setInterface(_:)))
            item.representedObject = name
            item.state = name == pinned ? .on : .off
            return item
        }
        return submenu("Interface", [automatic, .separator()] + choices)
    }

    /// Fills the Top Apps submenu after a one-second nettop sample. The menu is
    /// open meanwhile, so it shows a placeholder and is updated in place.
    private func sampleTopApps(into menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(readOnly("Measuring…"))
        appsTask?.cancel()
        let format = RateFormat(unit: state.rateUnit, autoScale: true) // per-app rates are usually small
        appsTask = Task { [weak self, weak menu] in
            let rows: [AppTraffic.Row]
            var failure: String?
            do { rows = try await AppTraffic.sample() } catch {
                rows = []
                failure = error.localizedDescription
            }
            guard let self, let menu, !Task.isCancelled else { return }
            menu.removeAllItems()
            if let failure {
                menu.addItem(self.readOnly("Unavailable: \(failure.prefix(60))"))
                return
            }
            let top = Self.topApps(rows)
            if top.isEmpty { menu.addItem(self.readOnly("No network activity")) }
            for app in top {
                let item = self.readOnly("\(app.name)   ↓ \(format.full(Double(app.down)))   ↑ \(format.full(Double(app.up)))")
                item.image = app.icon
                menu.addItem(item)
            }
        }
    }

    /// Groups rows by app name (helpers share their app's name when it is a
    /// registered app) and keeps the busiest few.
    private static func topApps(_ rows: [AppTraffic.Row]) -> [(name: String, down: Int64, up: Int64, icon: NSImage?)] {
        var byName: [String: (down: Int64, up: Int64, icon: NSImage?)] = [:]
        for row in rows where row.downBytes + row.upBytes > 0 {
            let app = NSRunningApplication(processIdentifier: row.pid)
            let name = app?.localizedName ?? row.name
            var entry = byName[name] ?? (0, 0, app?.icon.map(Self.menuIcon))
            entry.down += row.downBytes
            entry.up += row.upBytes
            byName[name] = entry
        }
        return byName
            .map { (name: $0.key, down: $0.value.down, up: $0.value.up, icon: $0.value.icon) }
            .sorted { $0.down + $0.up > $1.down + $1.up }
            .prefix(topAppsLimit)
            .map { $0 }
    }

    private static func menuIcon(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    // MARK: - Menu item helpers

    /// An info row: no action → AppKit auto-disables it (greyed, non-clickable).
    private func readOnly(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    // MARK: - Actions

    @objc private func resetTotals() { state.resetSessionTotals() }

    @objc private func runSpeedTest() { state.runSpeedTest() }

    @objc private func setInterval(_ sender: NSMenuItem) {
        if let seconds = sender.representedObject as? Double { state.updateInterval = seconds }
    }

    @objc private func setUnit(_ sender: NSMenuItem) {
        if let unit = (sender.representedObject as? String).flatMap(RateUnit.init) { state.rateUnit = unit }
    }

    @objc private func toggleAutoScale() { state.autoScale.toggle() }

    @objc private func setInterface(_ sender: NSMenuItem) {
        state.pinnedInterface = sender.representedObject as? String
    }

    @objc private func toggleLogin() { state.setAutoLaunch(!state.autoLaunchEnabled) }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Formatting

    private static func intervalLabel(_ seconds: Double) -> String {
        seconds < 1 ? String(format: "%.1fs", seconds) : String(format: "%.0fs", seconds)
    }

    private static let appVersion =
        "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
}
