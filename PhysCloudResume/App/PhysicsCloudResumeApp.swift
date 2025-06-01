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
    private let modelContainer: ModelContainer
    
    init() {
        // Create the model container first
        do {
            // Try with current models directly
            let container = try ModelContainer(for: 
                JobApp.self,
                Resume.self,
                ResRef.self,
                TreeNode.self,
                FontSizeNode.self,
                CoverLetter.self,
                MessageParams.self,
                CoverRef.self,
                ApplicantProfile.self,
                ResModel.self,
                ConversationContext.self,
                ConversationMessage.self
            )
            self.modelContainer = container
            Logger.debug("✅ ModelContainer created with current models")
        } catch {
            Logger.error("❌ Failed to create ModelContainer: \(error)")
            fatalError("Failed to create ModelContainer: \(error)")
        }
        
        // Log after all properties are initialized
        Logger.debug("🔴 PhysicsCloudResumeApp init - appState address: \(Unmanaged.passUnretained(appState).toOpaque())")
    }

    var body: some Scene {
        Window("Physics Cloud Résumé", id: "myApp") {
            ContentViewLaunch() // ContentView handles its own JobAppStore initialization
                .environment(appState)
                .onAppear {
                    // Pass appState to AppDelegate so it can use it for settings window
                    appDelegate.appState = appState
                }
        }
        .modelContainer(modelContainer)
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
    static let defaultValue: AppState? = nil
}

extension EnvironmentValues {
    var appState: AppState {
        get { 
            guard let state = self[AppStateKey.self] else {
                fatalError("AppState not found in environment. Make sure to provide it via .environment(appState)")
            }
            return state
        }
        set { self[AppStateKey.self] = newValue }
    }
}
