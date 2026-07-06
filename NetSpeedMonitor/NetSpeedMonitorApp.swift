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

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        state.onUpdate = { [weak self] in self?.refreshIcon() }
        refreshIcon()
    }

    /// The menu-bar number keeps ticking live even while the menu is open.
    private func refreshIcon() {
        statusItem.button?.image = state.currentIcon
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let down = state.sessionDownloadBytes.formatted(.byteCount(style: .binary))
        let up = state.sessionUploadBytes.formatted(.byteCount(style: .binary))
        menu.addItem(readOnly("↓ \(down) received"))
        menu.addItem(readOnly("↑ \(up) sent"))
        menu.addItem(action("Reset Session Totals", #selector(resetTotals)))

        menu.addItem(.separator())

        let intervalItem = NSMenuItem(title: "Update Interval", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for seconds in MenuBarState.intervalOptions {
            let item = action(Self.intervalLabel(seconds), #selector(setInterval(_:)))
            item.representedObject = seconds
            item.state = seconds == state.updateInterval ? .on : .off
            submenu.addItem(item)
        }
        intervalItem.submenu = submenu
        menu.addItem(intervalItem)

        let login = action("Launch at Login", #selector(toggleLogin))
        login.state = state.autoLaunchEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(readOnly("NetSpeedMonitor \(Self.appVersion)"))
        menu.addItem(action("Quit", #selector(quit)))
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

    // MARK: - Actions

    @objc private func resetTotals() { state.resetSessionTotals() }

    @objc private func setInterval(_ sender: NSMenuItem) {
        if let seconds = sender.representedObject as? Double { state.updateInterval = seconds }
    }

    @objc private func toggleLogin() { state.autoLaunchEnabled.toggle() }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Formatting

    private static func intervalLabel(_ seconds: Double) -> String {
        seconds < 1 ? String(format: "%.1fs", seconds) : String(format: "%.0fs", seconds)
    }

    private static let appVersion =
        "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
}
