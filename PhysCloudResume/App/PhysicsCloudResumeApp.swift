//
//  PhysicsCloudResumeApp.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

import Foundation
import SwiftData
import SwiftUI

@main
struct PhysicsCloudResumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Bindable private var appState = AppState()
    
    init() {
        Logger.debug("🔴 PhysicsCloudResumeApp init - appState address: \(Unmanaged.passUnretained(appState).toOpaque())")
    }

    var body: some Scene {
        Window("Physics Cloud Résumé", id: "myApp") {
            ContentViewLaunch() // ContentView handles its own JobAppStore initialization
                .environment(appState)
                .environmentObject(appState.modelService)
        }
        .modelContainer(
            for: SchemaV3.models,
            migrationPlan: PhysCloudResumeMigrationPlan.self
        )
        .windowToolbarStyle(UnifiedWindowToolbarStyle(showsTitle: false))
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appDelegate.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)

                Divider()

                Button("Applicant Profile...") {
                    appDelegate.showApplicantProfileWindow()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            
            CommandGroup(after: .importExport) {
                Button("Import Job Applications from URLs...") {
                    Logger.debug("🔵 Menu item clicked - Import Job Applications")
                    Logger.debug("🔵 appState address in menu: \(Unmanaged.passUnretained(appState).toOpaque())")
                    Logger.debug("🔵 Setting appState.showImportJobAppsSheet = true")
                    appState.showImportJobAppsSheet = true
                    Logger.debug("🔵 appState.showImportJobAppsSheet is now: \(appState.showImportJobAppsSheet)")
                    
                    // Try to trigger the import directly via notification
                    NotificationCenter.default.post(name: NSNotification.Name("ShowImportJobApps"), object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
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
