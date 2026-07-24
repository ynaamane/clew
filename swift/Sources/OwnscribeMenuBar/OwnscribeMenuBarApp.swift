import SwiftUI

@main
struct OwnscribeMenuBarApp: App {
    @State private var appState = AppState()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("ownscribe", systemImage: appState.isMuted ? "mic.slash" : "waveform") {
            MenuBarContentView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
