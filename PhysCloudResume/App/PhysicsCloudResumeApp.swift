//
//  PhysicsCloudResumeApp.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Menu Command Notifications
extension Notification.Name {
    // Job Application Commands
    static let newJobApp = Notification.Name("newJobApp")
    static let bestJob = Notification.Name("bestJob")
    static let showSources = Notification.Name("showSources")
    
    // Resume Commands
    static let customizeResume = Notification.Name("customizeResume")
    static let clarifyCustomize = Notification.Name("clarifyCustomize")
    static let optimizeResume = Notification.Name("optimizeResume")
    static let showResumeInspector = Notification.Name("showResumeInspector")
    
    // Cover Letter Commands
    static let generateCoverLetter = Notification.Name("generateCoverLetter")
    static let batchCoverLetter = Notification.Name("batchCoverLetter")
    static let bestCoverLetter = Notification.Name("bestCoverLetter")
    static let committee = Notification.Name("committee")
    static let showCoverLetterInspector = Notification.Name("showCoverLetterInspector")
    
    // Analysis Commands
    static let analyzeApplication = Notification.Name("analyzeApplication")
    
    // Window Commands (for toolbar buttons)
    static let showSettings = Notification.Name("showSettings")
    static let showApplicantProfile = Notification.Name("showApplicantProfile")
    static let showTemplateEditor = Notification.Name("showTemplateEditor")
}

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
            Logger.error("x Failed to create ModelContainer: \(error)")
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
                    // Pass appState and modelContainer to AppDelegate so it can use them for windows
                    appDelegate.appState = appState
                    appDelegate.modelContainer = modelContainer
                }
        }
        .modelContainer(modelContainer)
        .windowToolbarStyle(.expanded)
        .commands {
            ToolbarCommands()
        }
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
                
                Button("Template Editor...") {
                    appDelegate.showTemplateEditorWindow()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
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
            
            // Job Application Menu
            CommandGroup(after: .newItem) {
                Button("New Job Application") {
                    NotificationCenter.default.post(name: .newJobApp, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                
                Button("Best Job Match") {
                    NotificationCenter.default.post(name: .bestJob, object: nil)
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Show Sources") {
                    NotificationCenter.default.post(name: .showSources, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
            
            // Resume Menu
            CommandGroup(before: .windowList) {
                Menu("Resume") {
                    Button("Customize Resume") {
                        NotificationCenter.default.post(name: .customizeResume, object: nil)
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    
                    Button("Clarify & Customize") {
                        NotificationCenter.default.post(name: .clarifyCustomize, object: nil)
                    }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                    
                    Button("Optimize Resume") {
                        NotificationCenter.default.post(name: .optimizeResume, object: nil)
                    }
                    .keyboardShortcut("o", modifiers: [.command])
                    
                    Divider()
                    
                    Button("Show Resume Inspector") {
                        NotificationCenter.default.post(name: .showResumeInspector, object: nil)
                    }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                }
            }
            
            // Cover Letter Menu
            CommandGroup(before: .windowList) {
                Menu("Cover Letter") {
                    Button("Generate Cover Letter") {
                        NotificationCenter.default.post(name: .generateCoverLetter, object: nil)
                    }
                    .keyboardShortcut("l", modifiers: [.command])
                    
                    Button("Batch Cover Letters") {
                        NotificationCenter.default.post(name: .batchCoverLetter, object: nil)
                    }
                    .keyboardShortcut("b", modifiers: [.command])
                    
                    Button("Best Cover Letter") {
                        NotificationCenter.default.post(name: .bestCoverLetter, object: nil)
                    }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                    
                    Button("Multi-Model Committee") {
                        NotificationCenter.default.post(name: .committee, object: nil)
                    }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                    
                    Divider()
                    
                    Button("Show Cover Letter Inspector") {
                        NotificationCenter.default.post(name: .showCoverLetterInspector, object: nil)
                    }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                }
            }
            
            // Analysis Menu
            CommandGroup(before: .windowList) {
                Menu("Analysis") {
                    Button("Analyze Application") {
                        NotificationCenter.default.post(name: .analyzeApplication, object: nil)
                    }
                    .keyboardShortcut("a", modifiers: [.command])
                }
            }
        }
    }
}

// Environment key for accessing AppState  
struct AppStateKey: EnvironmentKey {
    static let defaultValue: AppState? = nil
}

extension EnvironmentValues {
    var appState: AppState {
        get { 
            // During early initialization (like window restoration), return a temporary AppState
            // that won't cause crashes but also won't interfere with the real one
            guard let appState = self[AppStateKey.self] else {
                // Use temporary fallback silently during early initialization
                return MainActor.assumeIsolated {
                    return TemporaryAppState.instance
                }
            }
            return appState
        }
        set { self[AppStateKey.self] = newValue }
    }
}

// Temporary AppState for early initialization
@MainActor
private class TemporaryAppState {
    static let instance: AppState = {
        // This creates a temporary AppState that's only used during early initialization
        // It will be replaced by the real AppState once the environment is properly set up
        return AppState()
    }()
}
