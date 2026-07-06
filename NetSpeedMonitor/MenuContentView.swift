import SwiftUI

/// The menu shown when the menu bar readout is clicked: session totals, the
/// refresh interval, the login toggle, version, and quit.
struct MenuContentView: View {
    @Environment(MenuBarState.self) private var menuBarState

    var body: some View {
        @Bindable var menuBarState = menuBarState

        Text("↓ \(menuBarState.sessionDownloadBytes.formatted(.byteCount(style: .binary))) received")
        Text("↑ \(menuBarState.sessionUploadBytes.formatted(.byteCount(style: .binary))) sent")
        Button("Reset Session Totals") { menuBarState.resetSessionTotals() }

        Divider()

        Picker("Update Interval", selection: $menuBarState.updateInterval) {
            ForEach(MenuBarState.intervalOptions, id: \.self) { seconds in
                Text(Self.intervalLabel(seconds)).tag(seconds)
            }
        }

        Toggle("Launch at Login", isOn: $menuBarState.autoLaunchEnabled)

        Divider()

        Text("NetSpeedMonitor \(Self.appVersion)")
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private static func intervalLabel(_ seconds: Double) -> String {
        seconds < 1 ? String(format: "%.1fs", seconds) : String(format: "%.0fs", seconds)
    }

    private static let appVersion =
        "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
}
