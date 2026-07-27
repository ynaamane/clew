import SwiftUI

@main
struct OwnscribeMenuBarApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Window("Réunions", id: LibraryWindow.sceneID) {
            LibraryWindow()
                .environment(appState)
                .onAppear { WindowActivationPolicy.windowDidOpen() }
                .onDisappear { WindowActivationPolicy.windowDidClose() }
        }
        .defaultSize(width: 1080, height: 660)

        MenuBarExtra("ownscribe", systemImage: appState.muteIndicator.symbolName) {
            MenuBarContentView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
