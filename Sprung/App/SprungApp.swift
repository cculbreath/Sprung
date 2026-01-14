//
//  SprungApp.swift
//  Sprung
//
//
import Foundation
import SwiftData
import SwiftUI
import AppKit
@main
struct SprungApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let modelContainer: ModelContainer
    private let appDependencies: AppDependencies
    private let appEnvironment: AppEnvironment
    init() {
        // Register default values for settings before any code reads them
        UserDefaults.standard.register(defaults: [
            "onboardingInterviewDefaultModelId": "gpt-5"
        ])

        // Perform any pending store reset from previous session (must happen before opening)
        SwiftDataBackupManager.performPendingResetIfNeeded()

        // Preflight backup before opening/migrating the store
        SwiftDataBackupManager.performPreflightBackupIfNeeded()
        var resolvedContainer: ModelContainer
        var launchState: AppEnvironment.LaunchState = .ready
        // Attempt to create the migration-aware container first
        do {
            resolvedContainer = try ModelContainer.createWithMigration()
            Logger.debug("✅ ModelContainer created with migration support (Schema V4)", category: .appLifecycle)
        } catch {
            Logger.error("❌ Failed to create ModelContainer with migrations: \(error)", category: .appLifecycle)
            do {
                resolvedContainer = try Self.makeDirectModelContainer()
                launchState = .readOnly(message: Self.migrationFailureMessage(from: error))
                Logger.warning("⚠️ Running in read-only mode using fallback ModelContainer without migration plan", category: .appLifecycle)
            } catch {
                Logger.error("❌ Failed to create fallback ModelContainer: \(error)", category: .appLifecycle)
                do {
                    let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    resolvedContainer = try Self.makeDirectModelContainer(configuration: inMemoryConfig)
                    launchState = .readOnly(message: Self.backupRestoreRequiredMessage(from: error))
                    Logger.error("🚨 Using in-memory ModelContainer; user data unavailable until restore completes", category: .appLifecycle)
                } catch {
                    Logger.error("❌ Failed to create temporary in-memory ModelContainer: \(error)", category: .appLifecycle)
                    let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    guard let fallbackContainer = try? Self.makeDirectModelContainer(configuration: inMemoryConfig) else {
                        preconditionFailure("Unable to create in-memory ModelContainer after migration failures: \(error)")
                    }
                    resolvedContainer = fallbackContainer
                    launchState = .readOnly(message: Self.backupRestoreRequiredMessage(from: error))
                }
            }
        }
        self.modelContainer = resolvedContainer
        let dependencies = AppDependencies(modelContext: resolvedContainer.mainContext)
        dependencies.appEnvironment.launchState = launchState
        dependencies.appEnvironment.appState.isReadOnlyMode = launchState.isReadOnly
        self.appDependencies = dependencies
        self.appEnvironment = dependencies.appEnvironment
    }
    var body: some Scene {
        Window("", id: "myApp") {
            ContentViewLaunch(deps: appDependencies)
                .environment(appEnvironment)
                .environment(appEnvironment.appState)
                .environment(appDependencies.navigationState)
                .environment(appDependencies.resumeExportCoordinator)
                .environment(appDependencies.templateStore)
                .environment(appDependencies.experienceDefaultsStore)
                .environment(appDependencies.careerKeywordStore)
                .environment(appDependencies.guidanceStore)
                .environment(appDependencies.candidateDossierStore)
                .onAppear {
                    // Pass environment and dependencies to AppDelegate for windows
                    appDelegate.appEnvironment = appEnvironment
                    appDelegate.modelContainer = modelContainer
                    appDelegate.enabledLLMStore = appDependencies.enabledLLMStore
                    appDelegate.applicantProfileStore = appDependencies.applicantProfileStore
                    appDelegate.experienceDefaultsStore = appDependencies.experienceDefaultsStore
                    appDelegate.careerKeywordStore = appDependencies.careerKeywordStore
                    appDelegate.guidanceStore = appDependencies.guidanceStore
                    appDelegate.onboardingCoordinator = appDependencies.onboardingCoordinator
                    appDelegate.searchOpsCoordinator = appDependencies.searchOpsCoordinator
                    appDelegate.coverRefStore = appDependencies.coverRefStore
                    appDelegate.knowledgeCardStore = appDependencies.knowledgeCardStore
                    appDelegate.skillStore = appDependencies.skillStore
                }
        }
        .modelContainer(modelContainer)
        .windowToolbarStyle(.expanded)
        .commands {
            ToolbarCommands()
        }
        // MARK: - Sprung App Menu
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Onboarding Interview...") {
                    Logger.info("🎙️ Menu command requested onboarding interview", category: .ui)
                    NotificationCenter.default.post(name: .startOnboardingInterview, object: nil)
                    appDelegate.showOnboardingInterviewWindow()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Setup Wizard...") {
                    NotificationCenter.default.post(name: .showSetupWizard, object: nil)
                }
                Divider()
                Button("Settings...") {
                    appDelegate.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        // MARK: - File Menu (Exports)
        .commands {
            CommandGroup(after: .importExport) {
                Menu("Export Resume") {
                    Button("as PDF") {
                        NotificationCenter.default.post(name: .exportResumePDF, object: nil)
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    Button("as Text") {
                        NotificationCenter.default.post(name: .exportResumeText, object: nil)
                    }
                    Button("as JSON") {
                        NotificationCenter.default.post(name: .exportResumeJSON, object: nil)
                    }
                }
                Menu("Export Cover Letter") {
                    Button("as PDF") {
                        NotificationCenter.default.post(name: .exportCoverLetterPDF, object: nil)
                    }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                    Button("as Text") {
                        NotificationCenter.default.post(name: .exportCoverLetterText, object: nil)
                    }
                    Button("All Variants") {
                        NotificationCenter.default.post(name: .exportAllCoverLetters, object: nil)
                    }
                }
                Button("Export Complete Application") {
                    NotificationCenter.default.post(name: .exportApplicationPacket, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])
            }
        }
        // MARK: - View Menu
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Show Resume Inspector") {
                    NotificationCenter.default.post(name: .showResumeInspector, object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Show Cover Letter Inspector") {
                    NotificationCenter.default.post(name: .showCoverLetterInspector, object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])
            }
        }
        // MARK: - Applicant Menu
        .commands {
            CommandMenu("Applicant") {
                Button("Applicant Profile...") {
                    appDelegate.showApplicantProfileWindow()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Experience Editor...") {
                    appDelegate.showExperienceEditorWindow()
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Generate Experience Defaults...") {
                    NotificationCenter.default.post(name: .showSeedGeneration, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Button("Knowledge Cards...") {
                    NotificationCenter.default.post(name: .toggleKnowledgeCards, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
                Button("Dossier & Writing Samples...") {
                    NotificationCenter.default.post(name: .showWritingContextBrowser, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .option])
            }
        }
        // MARK: - Listing Menu
        .commands {
            CommandMenu("Listing") {
                Button("New Listing") {
                    NotificationCenter.default.post(name: .newJobApp, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Best Job Match") {
                    NotificationCenter.default.post(name: .bestJob, object: nil)
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                Divider()
                Button("Analyze Application") {
                    NotificationCenter.default.post(name: .analyzeApplication, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Analyze All Pending Jobs") {
                    NotificationCenter.default.post(name: .preprocessAllPendingJobs, object: nil)
                }
                Button("Re-run All Job Pre-processing") {
                    NotificationCenter.default.post(name: .rerunAllJobPreprocessing, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .option, .shift])
            }
        }
        // MARK: - Resume Menu
        .commands {
            CommandMenu("Resume") {
                Button("Create New Resume") {
                    NotificationCenter.default.post(name: .createNewResume, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
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
                Button("Template Editor...") {
                    appDelegate.showTemplateEditorWindow()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
        // MARK: - Cover Letter Menu
        .commands {
            CommandMenu("Cover Letter") {
                Button("Generate Cover Letter") {
                    NotificationCenter.default.post(name: .generateCoverLetter, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command])
                Divider()
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
                Menu("Speech") {
                    Button("Start Speaking") {
                        NotificationCenter.default.post(name: .startSpeaking, object: nil)
                    }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    Button("Stop Speaking") {
                        NotificationCenter.default.post(name: .stopSpeaking, object: nil)
                    }
                    .keyboardShortcut(".", modifiers: [.command, .control])
                    Button("Restart Speaking") {
                        NotificationCenter.default.post(name: .restartSpeaking, object: nil)
                    }
                    .keyboardShortcut("r", modifiers: [.command, .control])
                }
            }
        }
        // MARK: - Discovery Menu (renamed from Search Ops)
        .commands {
            CommandMenu("Discovery") {
                Button("Open Discovery") {
                    Logger.info("🔍 Menu command requested Discovery window", category: .ui)
                    NotificationCenter.default.post(name: .showDiscovery, object: nil)
                    appDelegate.showDiscoveryWindow()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Start Discovery Interview...") {
                    NotificationCenter.default.post(name: .startDiscoveryInterview, object: nil)
                }
                Divider()
                Button("Discover Job Sources") {
                    NotificationCenter.default.post(name: .discoverJobSources, object: nil)
                }
                Button("Discover Networking Events") {
                    NotificationCenter.default.post(name: .discoverNetworkingEvents, object: nil)
                }
                Button("Generate Daily Tasks") {
                    NotificationCenter.default.post(name: .generateDailyTasks, object: nil)
                }
                Button("Generate Weekly Reflection") {
                    NotificationCenter.default.post(name: .generateWeeklyReflection, object: nil)
                }
                Divider()
                Button("Job Sources") {
                    NotificationCenter.default.post(name: .showDiscoveryJobSources, object: nil)
                }
                Button("Contacts & Network") {
                    NotificationCenter.default.post(name: .showDiscoveryContacts, object: nil)
                }
                Button("Events") {
                    NotificationCenter.default.post(name: .showDiscoveryEvents, object: nil)
                }
                Button("Daily Briefing") {
                    NotificationCenter.default.post(name: .showDiscoveryDailyBriefing, object: nil)
                }
                Button("Weekly Review") {
                    NotificationCenter.default.post(name: .showDiscoveryWeeklyReview, object: nil)
                }
            }
        }
        // MARK: - Window Menu
        .commands {
            CommandGroup(before: .windowArrangement) {
                Divider()
            }
        }
    }
}
private extension SprungApp {
    static func makeDirectModelContainer(configuration: ModelConfiguration? = nil) throws -> ModelContainer {
        let config: ModelConfiguration
        if let configuration {
            config = configuration
        } else {
            // Use same store location as createWithMigration for consistency
            config = ModelConfiguration(url: ModelContainer.storeURL, allowsSave: true)
        }
        return try ModelContainer(
            for:
                JobApp.self,
                Resume.self,
                KnowledgeCard.self,
                TreeNode.self,
                FontSizeNode.self,
                CoverLetter.self,
                CoverRef.self,
                ApplicantProfile.self,
                ConversationContext.self,
                ConversationMessage.self,
                EnabledLLM.self,
                InferenceGuidance.self,
            configurations: config
        )
    }
    static func migrationFailureMessage(from error: Error) -> String {
        """
        Sprung couldn't prepare its data store (migration error: \(error.localizedDescription)).
        The app is running in read-only mode so you can review existing information.
        Try restoring the latest backup below, then quit and relaunch the app to resume editing.
        """
    }
    static func backupRestoreRequiredMessage(from error: Error) -> String {
        """
        Sprung couldn't open its data files (error: \(error.localizedDescription)).
        The app is showing temporary in-memory data only. Restore the most recent backup below, then quit and relaunch to reload your information.
        Backups live in ~/Library/Application Support/Sprung_Backups.
        """
    }
}
