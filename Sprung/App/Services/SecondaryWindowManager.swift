//
//  SecondaryWindowManager.swift
//  Sprung
//
//  Owns the lifetime and presentation of all secondary NSWindow instances.
//  Extracted from AppDelegate to give each window a single, focused home.
//
import Cocoa
import SwiftData
import SwiftUI

@Observable
@MainActor
final class SecondaryWindowManager {
    // MARK: - Window References

    var settingsWindow: NSWindow?
    var applicantProfileWindow: NSWindow?
    var templateEditorWindow: NSWindow?
    var onboardingInterviewWindow: NSWindow?
    var experienceEditorWindow: NSWindow?
    var searchOpsWindow: NSWindow?
    var debugLogsWindow: NSWindow?
    var seedGenerationWindow: NSWindow?
    var resumeRevisionWindow: NSWindow?
    var backgroundActivityWindow: NSWindow?

    // MARK: - Dependencies (assigned from SprungApp.onAppear)

    var appEnvironment: AppEnvironment?
    var modelContainer: ModelContainer?
    var enabledLLMStore: EnabledLLMStore?
    var applicantProfileStore: ApplicantProfileStore?
    var onboardingCoordinator: OnboardingInterviewCoordinator?
    var experienceDefaultsStore: ExperienceDefaultsStore?
    var careerKeywordStore: CareerKeywordStore?
    var guidanceStore: InferenceGuidanceStore?
    var searchOpsCoordinator: DiscoveryCoordinator?
    var coverRefStore: CoverRefStore?
    var knowledgeCardStore: KnowledgeCardStore?
    var skillStore: SkillStore?
    var templateStore: TemplateStore?
    var titleSetStore: TitleSetStore?
    var candidateDossierStore: CandidateDossierStore?
    var jobAppStore: JobAppStore?
    var backgroundActivityTracker: BackgroundActivityTracker?

    // MARK: - Settings Window

    func showSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingView: NSHostingView<AnyView>
            if let appEnvironment = self.appEnvironment,
               let container = self.modelContainer,
               let enabledLLMStore = self.enabledLLMStore,
               let applicantProfileStore = self.applicantProfileStore,
               let experienceDefaultsStore = self.experienceDefaultsStore,
               let careerKeywordStore = self.careerKeywordStore,
               let guidanceStore = self.guidanceStore,
               let searchOpsCoordinator = self.searchOpsCoordinator,
               let skillStore = self.skillStore,
               let jobAppStore = self.jobAppStore,
               let titleSetStore = self.titleSetStore {
                let appState = appEnvironment.appState
                let debugSettingsStore = appState.debugSettingsStore ?? appEnvironment.debugSettingsStore
                let root = settingsView
                    .environment(appEnvironment)
                    .environment(appState)
                    .environment(appEnvironment.navigationState)
                    .environment(appEnvironment.onboardingCoordinator)
                    .environment(appEnvironment.llmFacade)
                    .environment(enabledLLMStore)
                    .environment(applicantProfileStore)
                    .environment(experienceDefaultsStore)
                    .environment(careerKeywordStore)
                    .environment(guidanceStore)
                    .environment(appEnvironment.openRouterService)
                    .environment(debugSettingsStore)
                    .environment(searchOpsCoordinator)
                    .environment(skillStore)
                    .environment(jobAppStore)
                    .environment(titleSetStore)
                    .modelContainer(container)
                hostingView = NSHostingView(rootView: AnyView(root))
            } else {
                Logger.warning(
                    "Settings window requested before environment is fully configured; dependencies missing",
                    category: .appLifecycle
                )
                hostingView = NSHostingView(
                    rootView: AnyView(
                        VStack(spacing: 16) {
                            Text("Settings Unavailable")
                                .font(.headline)
                            Text("App services are still loading. Please try opening Settings again in a moment.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 320, minHeight: 160)
                        .padding()
                    )
                )
            }
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            settingsWindow?.title = "Settings"
            settingsWindow?.contentView = hostingView
            settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.center()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Applicant Profile Window

    func showApplicantProfile() {
        if let window = applicantProfileWindow, !window.isVisible {
            applicantProfileWindow = nil
        }
        if applicantProfileWindow == nil {
            let profileView = ApplicantProfileView()
            let hostingView: NSHostingView<AnyView>
            if let appEnvironment,
               let container = modelContainer,
               let applicantProfileStore,
               let guidanceStore {
                let root = profileView
                    .environment(appEnvironment)
                    .environment(appEnvironment.appState)
                    .environment(applicantProfileStore)
                    .environment(appEnvironment.experienceDefaultsStore)
                    .environment(appEnvironment.careerKeywordStore)
                    .environment(guidanceStore)
                    .modelContainer(container)
                hostingView = NSHostingView(rootView: AnyView(root))
            } else if let container = modelContainer {
                let root = profileView.modelContainer(container)
                hostingView = NSHostingView(rootView: AnyView(root))
            } else {
                hostingView = NSHostingView(rootView: AnyView(profileView))
            }
            applicantProfileWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            applicantProfileWindow?.title = "Applicant Profile"
            applicantProfileWindow?.contentView = hostingView
            applicantProfileWindow?.isReleasedWhenClosed = false
            applicantProfileWindow?.center()
            applicantProfileWindow?.minSize = NSSize(width: 500, height: 520)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: applicantProfileWindow
            )
        }
        applicantProfileWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Window Close Handler

    @objc func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == applicantProfileWindow {
            applicantProfileWindow = nil
        } else if notification.object as? NSWindow == templateEditorWindow {
            templateEditorWindow = nil
        } else if notification.object as? NSWindow == experienceEditorWindow {
            experienceEditorWindow = nil
        } else if notification.object as? NSWindow == resumeRevisionWindow {
            resumeRevisionWindow = nil
        }
    }

    // MARK: - Template Editor Window

    func showTemplateEditor() {
        if let window = templateEditorWindow, !window.isVisible {
            templateEditorWindow = nil
        }
        if templateEditorWindow == nil {
            let editorView = TemplateEditorView()
            let hostingView: NSHostingView<AnyView>
            if let modelContainer = self.modelContainer,
               let appEnvironment = self.appEnvironment,
               let guidanceStore = self.guidanceStore {
                hostingView = NSHostingView(rootView: AnyView(
                    editorView
                        .modelContainer(modelContainer)
                        .environment(appEnvironment)
                        .environment(appEnvironment.appState)
                        .environment(appEnvironment.navigationState)
                        .environment(appEnvironment.experienceDefaultsStore)
                        .environment(appEnvironment.careerKeywordStore)
                        .environment(appEnvironment.applicantProfileStore)
                        .environment(guidanceStore)
                ))
            } else if let modelContainer = self.modelContainer {
                hostingView = NSHostingView(rootView: AnyView(editorView.modelContainer(modelContainer)))
            } else {
                hostingView = NSHostingView(rootView: AnyView(editorView))
            }
            templateEditorWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            templateEditorWindow?.title = "Template Editor"
            templateEditorWindow?.tabbingMode = .disallowed
            templateEditorWindow?.contentView = hostingView
            templateEditorWindow?.isReleasedWhenClosed = false
            templateEditorWindow?.center()
            templateEditorWindow?.minSize = NSSize(width: 960, height: 640)
        }
        templateEditorWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Onboarding Interview Window

    func showOnboardingInterview() {
        Logger.info(
            "showOnboardingInterviewWindow invoked (existing window: \(onboardingInterviewWindow != nil))",
            category: .ui
        )
        var shouldAnimatePresentation = false
        if let window = onboardingInterviewWindow, !window.isVisible {
            onboardingInterviewWindow = nil
            shouldAnimatePresentation = true
        }
        if onboardingInterviewWindow == nil {
            let interviewView = OnboardingInterviewView()
            let hostingView: NSHostingView<AnyView>
            if let modelContainer,
               let appEnvironment,
               let enabledLLMStore,
               let coverRefStore,
               let guidanceStore {
                let onboardingService = onboardingCoordinator ?? appEnvironment.onboardingCoordinator
                let debugSettingsStore = appEnvironment.appState.debugSettingsStore ?? appEnvironment.debugSettingsStore
                let root = interviewView
                    .modelContainer(modelContainer)
                    .environment(appEnvironment)
                    .environment(appEnvironment.appState)
                    .environment(appEnvironment.navigationState)
                    .environment(enabledLLMStore)
                    .environment(coverRefStore)
                    .environment(appEnvironment.applicantProfileStore)
                    .environment(appEnvironment.experienceDefaultsStore)
                    .environment(guidanceStore)
                    .environment(onboardingService)
                    .environment(onboardingService.toolRouter)
                    .environment(debugSettingsStore)
                hostingView = NSHostingView(rootView: AnyView(root))
            } else if let modelContainer {
                hostingView = NSHostingView(rootView: AnyView(interviewView.modelContainer(modelContainer)))
            } else {
                hostingView = NSHostingView(rootView: AnyView(interviewView))
            }
            let innerXPadding: CGFloat = 32 * 2        // = 64
            let minCardWidth = 1040 + innerXPadding    // = 1104
            let outerPad: CGFloat = 30                 // same as shadowR (left/right)
            let windowW = minCardWidth + outerPad*2    // = 1164
            onboardingInterviewWindow = BorderlessOverlayWindow(
                contentRect: NSRect(x: 0, y: 0, width: windowW, height: 700)
            )
            hostingView.wantsLayer = true
            hostingView.layer?.masksToBounds = true
            hostingView.layer?.cornerRadius = 44
            hostingView.layer?.cornerCurve = .continuous
            onboardingInterviewWindow?.contentView = hostingView
            onboardingInterviewWindow?.isReleasedWhenClosed = false
            onboardingInterviewWindow?.center()
            onboardingInterviewWindow?.minSize = NSSize(width: windowW, height: 600)
            Logger.info("Created onboarding interview window", category: .ui)
            shouldAnimatePresentation = true
        }
        guard let window = onboardingInterviewWindow else {
            Logger.error("Onboarding interview window is nil after setup", category: .ui)
            return
        }
        if shouldAnimatePresentation {
            OnboardingWindowAnimator.present(window)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        Logger.info("Onboarding interview window presented", category: .ui)
    }

    // MARK: - Discovery Window

    func showDiscovery(
        section: DiscoverySection? = nil,
        startOnboarding: Bool = false,
        triggerDiscovery: Bool = false,
        triggerEventDiscovery: Bool = false,
        triggerTaskGeneration: Bool = false,
        triggerWeeklyReflection: Bool = false
    ) {
        Logger.info("showDiscoveryWindow invoked (section: \(section?.rawValue ?? "nil"), onboarding: \(startOnboarding))", category: .ui)
        if let window = searchOpsWindow, !window.isVisible {
            searchOpsWindow = nil
        }
        if searchOpsWindow == nil {
            let searchOpsView = DiscoveryMainView()
            let hostingView: NSHostingView<AnyView>
            if let modelContainer,
               let appEnvironment,
               let searchOpsCoordinator,
               let coverRefStore,
               let knowledgeCardStore,
               let applicantProfileStore,
               let guidanceStore,
               let candidateDossierStore {
                let root = searchOpsView
                    .modelContainer(modelContainer)
                    .environment(appEnvironment)
                    .environment(appEnvironment.appState)
                    .environment(searchOpsCoordinator)
                    .environment(coverRefStore)
                    .environment(knowledgeCardStore)
                    .environment(applicantProfileStore)
                    .environment(guidanceStore)
                    .environment(candidateDossierStore)
                hostingView = NSHostingView(rootView: AnyView(root))
            } else if let modelContainer {
                hostingView = NSHostingView(rootView: AnyView(searchOpsView.modelContainer(modelContainer)))
            } else {
                hostingView = NSHostingView(rootView: AnyView(searchOpsView))
            }
            searchOpsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            searchOpsWindow?.contentView = hostingView
            searchOpsWindow?.title = "Discovery"
            searchOpsWindow?.isReleasedWhenClosed = false
            searchOpsWindow?.center()
            searchOpsWindow?.minSize = NSSize(width: 700, height: 500)
        }
        searchOpsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Post notifications for navigation and AI actions after window is shown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if startOnboarding {
                NotificationCenter.default.post(name: .discoveryStartOnboarding, object: nil)
            }
            if let section {
                NotificationCenter.default.post(name: .discoveryNavigateToSection, object: nil, userInfo: ["section": section])
            }
            if triggerDiscovery {
                NotificationCenter.default.post(name: .discoveryTriggerSourceDiscovery, object: nil)
            }
            if triggerEventDiscovery {
                NotificationCenter.default.post(name: .discoveryTriggerEventDiscovery, object: nil)
            }
            if triggerTaskGeneration {
                NotificationCenter.default.post(name: .discoveryTriggerTaskGeneration, object: nil)
            }
            if triggerWeeklyReflection, let coordinator = self?.searchOpsCoordinator {
                Task {
                    do {
                        try await coordinator.generateWeeklyReflection()
                    } catch {
                        Logger.error("Failed to generate weekly reflection: \(error)", category: .ai)
                    }
                }
            }
        }
        Logger.info("Discovery window presented", category: .ui)
    }

    // MARK: - Experience Editor Window

    func showExperienceEditor() {
        if let window = experienceEditorWindow, !window.isVisible {
            experienceEditorWindow = nil
        }
        if experienceEditorWindow == nil {
            let editorView = ExperienceEditorView()
            let hostingView: NSHostingView<AnyView>
            if let modelContainer,
               let appEnvironment,
               let experienceDefaultsStore,
               let guidanceStore {
                hostingView = NSHostingView(rootView: AnyView(
                    editorView
                        .modelContainer(modelContainer)
                        .environment(appEnvironment)
                        .environment(appEnvironment.appState)
                        .environment(experienceDefaultsStore)
                        .environment(appEnvironment.careerKeywordStore)
                        .environment(guidanceStore)
                ))
            } else if let modelContainer,
                      let experienceDefaultsStore,
                      let careerKeywordStore {
                hostingView = NSHostingView(rootView: AnyView(
                    editorView
                        .modelContainer(modelContainer)
                        .environment(experienceDefaultsStore)
                        .environment(careerKeywordStore)
                ))
            } else if let experienceDefaultsStore,
                      let careerKeywordStore {
                hostingView = NSHostingView(rootView: AnyView(
                    editorView
                        .environment(experienceDefaultsStore)
                        .environment(careerKeywordStore)
                ))
            } else {
                hostingView = NSHostingView(rootView: AnyView(editorView))
            }
            experienceEditorWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            experienceEditorWindow?.title = "Experience Editor"
            experienceEditorWindow?.tabbingMode = .disallowed
            experienceEditorWindow?.contentView = hostingView
            experienceEditorWindow?.isReleasedWhenClosed = false
            experienceEditorWindow?.center()
            experienceEditorWindow?.minSize = NSSize(width: 960, height: 680)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: experienceEditorWindow
            )
        }
        experienceEditorWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Resume Revision Window

    func showResumeRevision() {
        guard let jobAppStore,
              let selectedResume = jobAppStore.selectedApp?.selectedRes else {
            Logger.warning("No resume selected for revision", category: .ui)
            return
        }

        if let window = resumeRevisionWindow, !window.isVisible {
            resumeRevisionWindow = nil
        }
        if resumeRevisionWindow == nil {
            let revisionView = ResumeRevisionView(resume: selectedResume)
            let hostingView: NSHostingView<AnyView>
            if let modelContainer,
               let appEnvironment,
               let templateStore,
               let knowledgeCardStore,
               let skillStore,
               let coverRefStore,
               let titleSetStore {
                hostingView = NSHostingView(rootView: AnyView(
                    revisionView
                        .modelContainer(modelContainer)
                        .environment(appEnvironment.llmFacade)
                        .environment(templateStore)
                        .environment(appEnvironment.applicantProfileStore)
                        .environment(knowledgeCardStore)
                        .environment(skillStore)
                        .environment(coverRefStore)
                        .environment(titleSetStore)
                ))
            } else {
                Logger.error("Missing dependencies for resume revision window", category: .ui)
                return
            }
            resumeRevisionWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1300, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            resumeRevisionWindow?.title = "Resume Revision"
            resumeRevisionWindow?.tabbingMode = .disallowed
            resumeRevisionWindow?.contentView = hostingView
            resumeRevisionWindow?.isReleasedWhenClosed = false
            resumeRevisionWindow?.center()
            resumeRevisionWindow?.minSize = NSSize(width: 1100, height: 650)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: resumeRevisionWindow
            )
        }
        resumeRevisionWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Debug Logs Window

    func showDebugLogs(coordinator: OnboardingInterviewCoordinator) {
        Logger.info("showDebugLogsWindow called", category: .ui)
        if let window = debugLogsWindow, !window.isVisible {
            debugLogsWindow = nil
        }
        if debugLogsWindow == nil {
            Logger.info("Creating debug logs window", category: .ui)
            let debugView = EventDumpView(coordinator: coordinator)
            let hostingView = NSHostingView(rootView: debugView)

            debugLogsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            debugLogsWindow?.title = "Debug Logs"
            debugLogsWindow?.contentView = hostingView
            debugLogsWindow?.isReleasedWhenClosed = false
            debugLogsWindow?.center()
            debugLogsWindow?.minSize = NSSize(width: 600, height: 400)
        }
        debugLogsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Seed Generation Window

    func showSeedGeneration() async {
        Logger.info("showSeedGenerationWindow called", category: .ui)

        // Reset window if it was closed
        if let window = seedGenerationWindow, !window.isVisible {
            seedGenerationWindow = nil
        }

        if seedGenerationWindow == nil {
            guard let onboardingCoordinator,
                  let appEnvironment,
                  let skillStore,
                  let experienceDefaultsStore,
                  let modelContainer else {
                Logger.error("Cannot show seed generation: missing dependencies", category: .ui)
                return
            }

            // Build SeedGenerationContext from onboarding artifacts
            guard let context = await SeedGenerationContextBuilder.build(
                coordinator: onboardingCoordinator,
                skillStore: skillStore,
                experienceDefaultsStore: experienceDefaultsStore,
                applicantProfileStore: applicantProfileStore,
                coverRefStore: coverRefStore,
                titleSetStore: titleSetStore
            ) else {
                Logger.error("Failed to build SeedGenerationContext", category: .ui)
                return
            }

            // Get model and backend from settings (per-backend model persistence)
            let backendString = UserDefaults.standard.string(forKey: "seedGenerationBackend") ?? "anthropic"
            let backend: LLMFacade.Backend = backendString == "anthropic" ? .anthropic : .openRouter
            let modelKey = backendString == "anthropic" ? "seedGenerationAnthropicModelId" : "seedGenerationOpenRouterModelId"
            guard let modelId = UserDefaults.standard.string(forKey: modelKey),
                  !modelId.isEmpty else {
                Logger.error("Cannot show seed generation: no model configured. Please select a model in Settings > Models.", category: .ui)
                return
            }

            let orchestrator = SeedGenerationOrchestrator(
                context: context,
                llmFacade: appEnvironment.llmFacade,
                modelId: modelId,
                backend: backend,
                experienceDefaultsStore: experienceDefaultsStore
            )

            let sgmView = SeedGenerationView(orchestrator: orchestrator)
            let hostingView: NSHostingView<AnyView>

            if let guidanceStore,
               let titleSetStore {
                let root = sgmView
                    .modelContainer(modelContainer)
                    .environment(appEnvironment)
                    .environment(appEnvironment.appState)
                    .environment(appEnvironment.llmFacade)
                    .environment(experienceDefaultsStore)
                    .environment(guidanceStore)
                    .environment(titleSetStore)
                hostingView = NSHostingView(rootView: AnyView(root))
            } else {
                hostingView = NSHostingView(rootView: AnyView(
                    sgmView.modelContainer(modelContainer)
                ))
            }

            seedGenerationWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            seedGenerationWindow?.title = "Seed Generation"
            seedGenerationWindow?.tabbingMode = .disallowed
            seedGenerationWindow?.contentView = hostingView
            seedGenerationWindow?.isReleasedWhenClosed = false
            seedGenerationWindow?.center()
            seedGenerationWindow?.minSize = NSSize(width: 800, height: 600)

            Logger.info("Created seed generation window", category: .ui)
        }

        seedGenerationWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Background Activity Window

    func showBackgroundActivity() {
        if let window = backgroundActivityWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let tracker = backgroundActivityTracker else {
            Logger.warning("Background activity tracker not configured", category: .appLifecycle)
            return
        }

        let contentView = BackgroundActivityContent(tracker: tracker)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Background Activity"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 500, height: 300)

        backgroundActivityWindow = window
        window.makeKeyAndOrderFront(nil)
    }
}
