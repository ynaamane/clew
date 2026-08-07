import SwiftUI

@main
struct OwnscribeMenuBarApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        UrlOpenHandler.shared.install()
    }

    var body: some Scene {
        Window("Réunions", id: LibraryWindow.sceneID) {
            LibraryWindow()
                .environment(appState)
                .onAppear { WindowActivationPolicy.shared.windowDidOpen() }
                .onDisappear { WindowActivationPolicy.shared.windowDidClose() }
        }
        .defaultSize(width: 1080, height: 660)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Ouvrir Clew") { showLibrary() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }

        MenuBarExtra("Clew", systemImage: appState.muteIndicator.symbolName) {
            MenuBarContentView()
                .environment(appState)
                .task { UrlOpenHandler.shared.openScene = { _ in showLibrary() } }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    private func showLibrary() {
        openWindow(id: LibraryWindow.sceneID)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
