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
    /// Set when a user-requested data-store reset was pending at launch but the
    /// deletion failed. Surfaced as a startup alert so the user isn't misled into
    /// believing their data was wiped (it survives). Nil on a normal launch.
    private let pendingResetFailureMessage: String?
    init() {
        // Test-host guard: when the XCTest bundle launches this app as its host, run the
        // entire app against an ephemeral in-memory store and skip every real-store side
        // effect (pending reset, preflight backup, on-disk migration). Without this, every
        // `xcodebuild test` run would read, back up, and potentially reset the developer's
        // real `default.store`. Tests build their own containers; the host's is throwaway.
        if Self.isRunningUnitTests {
            guard let container = try? ModelContainer(
                for: SprungSchema.schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            ) else {
                preconditionFailure("Unable to create in-memory ModelContainer for the test host")
            }
            self.modelContainer = container
            let dependencies = AppDependencies(modelContext: container.mainContext)
            self.appDependencies = dependencies
            self.appEnvironment = dependencies.appEnvironment
            self.pendingResetFailureMessage = nil
            return
        }

        // Perform any pending store reset from previous session (must happen before opening).
        // A failed reset means the user asked to wipe their data but it survives — capture
        // that so the launch can alert them instead of silently leaving the data in place.
        switch SwiftDataBackupService.performPendingResetIfNeeded() {
        case let .failed(reason):
            self.pendingResetFailureMessage = Self.pendingResetFailureText(reason: reason)
        case .notRequested, .completed, .nothingToDelete:
            self.pendingResetFailureMessage = nil
        }

        // Preflight backup before opening/migrating the store
        SwiftDataBackupService.performPreflightBackupIfNeeded()
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
                .environment(appDependencies.candidateDossierStore)
                .environment(appDependencies.moduleNavigation)
                .environment(appDependencies.focusState)
                .environment(appDependencies.windowCoordinator)
                .environment(appDependencies.backgroundActivityTracker)
                .onAppear {
                    // Hand the composition root to the window manager (one-shot)
                    // so every secondary window resolves its dependencies from it.
                    appDelegate.windowManager.configure(deps: appDependencies)
                    appDelegate.setupMainWindowToolbar()
                    presentPendingResetFailureAlertIfNeeded()
                }
        }
        .modelContainer(modelContainer)
        // Make the content's declared minWidth/minHeight (set on UnifiedAppLayout)
        // an actual hard floor for the window. Without this the default
        // `.automatic` resizability lets the window be dragged narrower than its
        // content minimum; the too-wide content then overflows and centers,
        // pushing the icon bar and jobs sidebar off the left edge into an
        // unreachable region.
        .windowResizability(.contentMinSize)
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
                Button("Toggle Job App Pane") {
                    NotificationCenter.default.post(name: .toggleJobAppPane, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                Divider()
                Button("Show Cover Letter Inspector") {
                    NotificationCenter.default.post(name: .showCoverLetterInspector, object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])
            }
        }
        // MARK: - Applicant Menu
        .commands {
            CommandMenu("Applicant") {
                Button("Profile") {
                    NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.profile.rawValue])
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Experience") {
                    NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.experience.rawValue])
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Generate Experience Defaults...") {
                    NotificationCenter.default.post(name: .showSeedGeneration, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Button("References") {
                    NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.references.rawValue])
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
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
        // MARK: - Discovery Menu (uses module navigation)
        .commands {
            CommandMenu("Discovery") {
                Button("Pipeline") {
                    Logger.info("Menu: navigating to Pipeline module", category: .ui)
                    NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.pipeline.rawValue])
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Start Discovery Interview...") {
                    NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.dailyTasks.rawValue])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .discoveryStartOnboarding, object: nil)
                    }
                }
                Divider()
                Button("Discover Networking Events") {
                    NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.events.rawValue])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .discoveryTriggerEventDiscovery, object: nil)
                    }
                }
                Button("Generate Daily Tasks") {
                    NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.dailyTasks.rawValue])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .discoveryTriggerTaskGeneration, object: nil)
                    }
                }
                Button("Generate Weekly Reflection") {
                    NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.weeklyReview.rawValue])
                }
                Divider()
                Button("Contacts & Network") {
                    NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.contacts.rawValue])
                }
                Button("Events") {
                    NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.events.rawValue])
                }
                Button("Daily Tasks") {
                    NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.dailyTasks.rawValue])
                }
                Button("Weekly Review") {
                    NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.weeklyReview.rawValue])
                }
            }
        }
        // MARK: - Window Menu
        .commands {
            CommandGroup(before: .windowArrangement) {
                Button("Background Activity") {
                    appDelegate.showBackgroundActivityWindow()
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
                Divider()
            }
        }
    }
}
private extension SprungApp {
    /// True when the process is hosting the XCTest bundle (set by Xcode/xcodebuild at
    /// launch). Used to keep the test host off the developer's real data store.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    static func makeDirectModelContainer(configuration: ModelConfiguration? = nil) throws -> ModelContainer {
        let config: ModelConfiguration
        if let configuration {
            config = configuration
        } else {
            // Use same store location as createWithMigration for consistency
            config = ModelConfiguration(url: ModelContainer.storeURL, allowsSave: true)
        }
        // Register the full schema (not a hand-maintained subset). This recovery
        // container runs precisely when migration already failed; registering only
        // some of the 34 model types would make the read-only safety net throw on
        // every unregistered entity.
        return try ModelContainer(
            for: SprungSchema.schema,
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
    static func pendingResetFailureText(reason: String) -> String {
        """
        Sprung couldn't remove your existing data during this launch, so your information is still on disk (reason: \(reason)).
        Nothing was erased. You can ask Sprung to try the reset again the next time it launches, or leave your data as it is.
        """
    }

    /// Shows a one-shot alert when a pending data-store reset failed at launch.
    /// Offers to re-arm the reset for the next launch so the user has a recovery
    /// path instead of silently keeping data they asked to delete.
    @MainActor
    func presentPendingResetFailureAlertIfNeeded() {
        guard let message = pendingResetFailureMessage else { return }
        // Defer one runloop tick so the main window is fully on screen before the
        // modal appears.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Data Reset Didn't Complete"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Try Again on Next Launch")
            if alert.runModal() == .alertSecondButtonReturn {
                do {
                    try SwiftDataBackupService.destroyCurrentStore()
                } catch {
                    Logger.error("❌ Failed to re-arm pending data-store reset: \(error.localizedDescription)", category: .appLifecycle)
                    let failureAlert = NSAlert()
                    failureAlert.alertStyle = .warning
                    failureAlert.messageText = "Couldn't Schedule Reset"
                    failureAlert.informativeText = "Sprung couldn't schedule the data reset for the next launch (reason: \(error.localizedDescription)). Your data is unchanged — please try again."
                    failureAlert.addButton(withTitle: "OK")
                    failureAlert.runModal()
                }
            }
        }
    }
}
