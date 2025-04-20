import Foundation
import SwiftUI

@main
struct PhysicsCloudResumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Bindable private var appState = AppState()

    var body: some Scene {
        Window("Physics Cloud Résumé", id: "myApp") {
            ContentViewLaunch() // ContentView handles its own JobAppStore initialization
                .environment(appState)
        }
        .modelContainer(for: [JobApp.self, Resume.self, ResRef.self, TreeNode.self, CoverLetter.self, MessageParams.self, CoverRef.self])
        .windowToolbarStyle(UnifiedWindowToolbarStyle(showsTitle: false))
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appDelegate.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

// Environment key for accessing AppState
private struct AppStateKey: EnvironmentKey {
    static let defaultValue = AppState()
}

extension EnvironmentValues {
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}