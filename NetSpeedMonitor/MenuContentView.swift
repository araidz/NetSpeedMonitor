import SwiftUI

/// The menu shown when the menu bar readout is clicked: just the login toggle
/// and a quit command.
struct MenuContentView: View {
    @Environment(MenuBarState.self) private var menuBarState

    var body: some View {
        @Bindable var menuBarState = menuBarState

        Toggle("Start at Login", isOn: $menuBarState.autoLaunchEnabled)

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
