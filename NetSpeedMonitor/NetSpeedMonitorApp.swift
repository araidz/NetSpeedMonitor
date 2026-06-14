import SwiftUI

@main
struct NetSpeedMonitorApp: App {
    @State private var menuBarState = MenuBarState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(menuBarState)
        } label: {
            Image(nsImage: menuBarState.currentIcon)
                .tag("MenuBarIcon")
        }
        .menuBarExtraStyle(.menu)
    }
}
