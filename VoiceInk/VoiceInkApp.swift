import SwiftUI

@main
struct VoiceInkApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updaterManager = UpdaterManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(updaterManager)
        }
    }
}
