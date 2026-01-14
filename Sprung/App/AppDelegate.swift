//
//  AppDelegate.swift
//  Sprung
//
//
import Cocoa
import QuartzCore
import SwiftData
import SwiftUI
class AppDelegate: NSObject, NSApplicationDelegate {
    var settingsWindow: NSWindow?
    var applicantProfileWindow: NSWindow?
    var templateEditorWindow: NSWindow?
    var onboardingInterviewWindow: NSWindow?
    var experienceEditorWindow: NSWindow?
    var searchOpsWindow: NSWindow?
    var debugLogsWindow: NSWindow?
    var seedGenerationWindow: NSWindow?
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
    func applicationDidFinishLaunching(_: Notification) {
        // Wait until the app is fully loaded before modifying the menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setupAppMenu()
        }
        // We no longer add a separate Profile main menu to avoid duplication

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowDebugLogs(_:)),
            name: .showDebugLogs,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSeedGeneration(_:)),
            name: .showSeedGeneration,
            object: nil
        )
    }
    private func setupAppMenu() {
        guard let mainMenu = NSApp.mainMenu else {
            return
        }
        // Find the name of the application to look for the right menu item
        let appName = ProcessInfo.processInfo.processName
        // Find or create the Application menu (first menu)
        let appMenu: NSMenu
        if let existingAppMenu = mainMenu.item(at: 0)?.submenu {
            appMenu = existingAppMenu
        } else {
            // Create a new app menu if it doesn't exist (unlikely)
            appMenu = NSMenu(title: appName)
            let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
            appMenuItem.submenu = appMenu
            mainMenu.insertItem(appMenuItem, at: 0)
        }
        // Find the About menu item with different possible titles
        let possibleAboutTitles = [
            "About \(appName)",
            "About Sprung",
            "About Physics Cloud Résumé"
        ]
        var aboutItemIndex = -1
        for title in possibleAboutTitles {
            let index = appMenu.indexOfItem(withTitle: title)
            if index >= 0 {
                aboutItemIndex = index
                break
            }
        }
        // If About item not found, insert at the beginning
        let aboutSeparatorIndex = aboutItemIndex >= 0 ? aboutItemIndex + 1 : 0
        // If we already have an Applicant Profile menu item, remove it to avoid duplicates
        let existingProfileIndex = appMenu.indexOfItem(withTitle: "Applicant Profile...")
        if existingProfileIndex >= 0 {
            appMenu.removeItem(at: existingProfileIndex)
        }
        // Insert separator if needed
        if aboutSeparatorIndex < appMenu.numberOfItems &&
            !appMenu.item(at: aboutSeparatorIndex)!.isSeparatorItem {
            appMenu.insertItem(NSMenuItem.separator(), at: aboutSeparatorIndex)
        }
        // Add Applicant Profile menu item after separator
        let profileMenuItem = NSMenuItem(
            title: "Applicant Profile...",
            action: #selector(showApplicantProfileWindow),
            keyEquivalent: ""
        )
        profileMenuItem.target = self
        appMenu.insertItem(profileMenuItem, at: aboutSeparatorIndex + 1)
        // Add Template Editor menu item
        let templateMenuItem = NSMenuItem(
            title: "Template Editor...",
            action: #selector(showTemplateEditorWindow),
            keyEquivalent: "T"
        )
        templateMenuItem.target = self
        templateMenuItem.keyEquivalentModifierMask = [.command, .shift]
        appMenu.insertItem(templateMenuItem, at: aboutSeparatorIndex + 2)
        let experienceMenuItem = NSMenuItem(
            title: "Experience Editor...",
            action: #selector(showExperienceEditorWindow),
            keyEquivalent: "E"
        )
        experienceMenuItem.keyEquivalentModifierMask = [.command, .shift]
        experienceMenuItem.target = self
        appMenu.insertItem(experienceMenuItem, at: aboutSeparatorIndex + 3)
    }
    @MainActor @objc func showSettingsWindow() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            // Create hosting view with proper environment objects
            let hostingView: NSHostingView<AnyView>
            if let appEnvironment = self.appEnvironment,
               let container = self.modelContainer,
               let enabledLLMStore = self.enabledLLMStore,
               let applicantProfileStore = self.applicantProfileStore,
               let experienceDefaultsStore = self.experienceDefaultsStore,
               let careerKeywordStore = self.careerKeywordStore,
               let guidanceStore = self.guidanceStore,
               let searchOpsCoordinator = self.searchOpsCoordinator,
               let skillStore = self.skillStore {
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
                    .modelContainer(container)
                hostingView = NSHostingView(rootView: AnyView(root))
            } else {
                // Fallback if appState or modelContainer is not available
                Logger.warning(
                    "⚠️ Settings window requested before environment is fully configured; dependencies missing",
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
            // Center the window on the screen
            settingsWindow?.center()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func showApplicantProfileWindow() {
        // If window exists but was closed, reset it
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
            // Set a minimum size for the window
            applicantProfileWindow?.minSize = NSSize(width: 500, height: 520)
            // Register for notifications when window is closed
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: applicantProfileWindow
            )
        }
        // Bring the window to the front
        applicantProfileWindow?.makeKeyAndOrderFront(nil)
        // Activate the app to ensure focus
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == applicantProfileWindow {
            applicantProfileWindow = nil
        } else if notification.object as? NSWindow == templateEditorWindow {
            templateEditorWindow = nil
        } else if notification.object as? NSWindow == experienceEditorWindow {
            experienceEditorWindow = nil
        }
    }
    @objc func showTemplateEditorWindow() {
        // If window exists but was closed, reset it
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
            // Set a minimum size for the window
            templateEditorWindow?.minSize = NSSize(width: 960, height: 640)
        }
        // Bring the window to the front
        templateEditorWindow?.makeKeyAndOrderFront(nil)
        // Activate the app to ensure focus
        NSApp.activate(ignoringOtherApps: true)
    }
    @MainActor @objc func showOnboardingInterviewWindow() {
        Logger.info(
            "🎬 showOnboardingInterviewWindow invoked (existing window: \(onboardingInterviewWindow != nil))",
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
            hostingView.layer?.cornerRadius = 44  // Match SwiftUI cardShape cornerRadius
            hostingView.layer?.cornerCurve = .continuous
            onboardingInterviewWindow?.contentView = hostingView
            onboardingInterviewWindow?.isReleasedWhenClosed = false
            onboardingInterviewWindow?.center()
            onboardingInterviewWindow?.minSize = NSSize(width: windowW, height: 600)
            Logger.info("🆕 Created onboarding interview window", category: .ui)
            shouldAnimatePresentation = true
        }
        guard let window = onboardingInterviewWindow else {
            Logger.error("❌ Onboarding interview window is nil after setup", category: .ui)
            return
        }
        if shouldAnimatePresentation {
            presentOnboardingInterviewWindowAnimated(window)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        Logger.info("✅ Onboarding interview window presented", category: .ui)
    }

    @MainActor
    private func presentOnboardingInterviewWindowAnimated(_ window: NSWindow) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.alphaValue = 1
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let finalFrame = window.frame
        let minHeight = window.minSize.height

        func frame(height: CGFloat, yOffset: CGFloat) -> NSRect {
            var next = finalFrame
            next.size.height = height
            let heightDelta = height - finalFrame.size.height
            next.origin.y = finalFrame.origin.y - (heightDelta / 2) + yOffset
            return next
        }

        let startHeight = max(finalFrame.size.height * 0.90, minHeight)
        let overshootHeight = max(finalFrame.size.height * 1.02, minHeight)
        let undershootHeight = max(finalFrame.size.height * 0.995, minHeight)

        let startFrame = frame(height: startHeight, yOffset: -120)
        let overshootFrame = frame(height: overshootHeight, yOffset: 18)
        let undershootFrame = frame(height: undershootHeight, yOffset: -6)

        window.alphaValue = 0
        window.setFrame(startFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(overshootFrame, display: true)
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(undershootFrame, display: true)
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(finalFrame, display: true)
                }
            }
        }
    }
    @MainActor @objc func showDiscoveryWindow() {
        showDiscoveryWindow(section: nil, startOnboarding: false, triggerDiscovery: false, triggerEventDiscovery: false, triggerTaskGeneration: false, triggerWeeklyReflection: false)
    }

    @MainActor func showDiscoveryWindow(
        section: DiscoverySection? = nil,
        startOnboarding: Bool = false,
        triggerDiscovery: Bool = false,
        triggerEventDiscovery: Bool = false,
        triggerTaskGeneration: Bool = false,
        triggerWeeklyReflection: Bool = false
    ) {
        Logger.info("🔍 showDiscoveryWindow invoked (section: \(section?.rawValue ?? "nil"), onboarding: \(startOnboarding))", category: .ui)
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
               let guidanceStore {
                let root = searchOpsView
                    .modelContainer(modelContainer)
                    .environment(appEnvironment)
                    .environment(appEnvironment.appState)
                    .environment(searchOpsCoordinator)
                    .environment(coverRefStore)
                    .environment(knowledgeCardStore)
                    .environment(applicantProfileStore)
                    .environment(guidanceStore)
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
        Logger.info("✅ Discovery window presented", category: .ui)
    }
    @objc func showExperienceEditorWindow() {
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

    @objc private func handleShowDebugLogs(_ notification: Notification) {
        Logger.info("🐞 Debug logs notification received", category: .ui)
        guard let coordinator = notification.object as? OnboardingInterviewCoordinator else {
            Logger.warning("⚠️ Debug logs notification missing coordinator", category: .ui)
            return
        }
        Task { @MainActor in
            self.showDebugLogsWindow(coordinator: coordinator)
        }
    }

    @MainActor func showDebugLogsWindow(coordinator: OnboardingInterviewCoordinator) {
        Logger.info("🐞 showDebugLogsWindow called", category: .ui)
        if let window = debugLogsWindow, !window.isVisible {
            debugLogsWindow = nil
        }
        if debugLogsWindow == nil {
            Logger.info("🐞 Creating debug logs window", category: .ui)
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

    // MARK: - Seed Generation

    @objc private func handleShowSeedGeneration(_ notification: Notification) {
        Logger.info("🌱 Seed generation notification received", category: .ui)
        Task { @MainActor in
            await self.showSeedGenerationWindow()
        }
    }

    @MainActor func showSeedGenerationWindow() async {
        Logger.info("🌱 showSeedGenerationWindow called", category: .ui)

        // Reset window if it was closed
        if let window = seedGenerationWindow, !window.isVisible {
            seedGenerationWindow = nil
        }

        if seedGenerationWindow == nil {
            guard let onboardingCoordinator,
                  let appEnvironment,
                  let skillStore,
                  let modelContainer else {
                Logger.error("🌱 Cannot show seed generation: missing dependencies", category: .ui)
                return
            }

            // Build SeedGenerationContext from onboarding artifacts
            guard let context = await buildSeedGenerationContext(
                coordinator: onboardingCoordinator,
                skillStore: skillStore
            ) else {
                Logger.error("🌱 Failed to build SeedGenerationContext", category: .ui)
                return
            }

            // Get model and backend from settings
            let backendString = UserDefaults.standard.string(forKey: "seedGenerationBackend") ?? "anthropic"
            let backend: LLMFacade.Backend = backendString == "anthropic" ? .anthropic : .openRouter
            let defaultModel = backend == .anthropic ? "claude-sonnet-4-20250514" : "anthropic/claude-sonnet-4"
            let modelId = UserDefaults.standard.string(forKey: "seedGenerationModelId") ?? defaultModel

            let orchestrator = SeedGenerationOrchestrator(
                context: context,
                llmFacade: appEnvironment.llmFacade,
                modelId: modelId,
                backend: backend
            )

            let sgmView = SeedGenerationView(orchestrator: orchestrator)
            let hostingView: NSHostingView<AnyView>

            if let experienceDefaultsStore,
               let guidanceStore {
                let root = sgmView
                    .modelContainer(modelContainer)
                    .environment(appEnvironment)
                    .environment(appEnvironment.appState)
                    .environment(experienceDefaultsStore)
                    .environment(guidanceStore)
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

            Logger.info("🌱 Created seed generation window", category: .ui)
        }

        seedGenerationWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func buildSeedGenerationContext(
        coordinator: OnboardingInterviewCoordinator,
        skillStore: SkillStore
    ) async -> SeedGenerationContext? {
        let artifacts = await coordinator.state.artifacts
        let knowledgeCards = coordinator.getKnowledgeCardStore().onboardingCards

        // Get writing samples from CoverRefStore (filter by type)
        let allCoverRefs = coverRefStore?.storedCoverRefs ?? []
        let writingSamples = allCoverRefs.filter { $0.type == .writingSample }
        let voicePrimer = allCoverRefs.first { $0.type == .voicePrimer }

        // Dossier is not used in current SGM implementation
        // Future: Could get from CandidateDossierStore if needed

        return SeedGenerationContext.build(
            from: artifacts,
            knowledgeCards: knowledgeCards,
            skills: skillStore.skills,
            writingSamples: writingSamples,
            voicePrimer: voicePrimer,
            dossier: nil
        )
    }

    // MARK: - URL Scheme Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleIncomingURL(url)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "sprung" else { return }

        Logger.info("📥 Received URL: \(url.absoluteString)", category: .appLifecycle)

        switch url.host {
        case "capture-job":
            // Extract the job URL from query parameters
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let jobURLString = components.queryItems?.first(where: { $0.name == "url" })?.value {
                // Post notification to open New Job App sheet with URL
                NotificationCenter.default.post(
                    name: .captureJobFromURL,
                    object: nil,
                    userInfo: ["url": jobURLString]
                )
                NSApp.activate(ignoringOtherApps: true)
            } else {
                Logger.warning("⚠️ capture-job URL missing 'url' parameter", category: .appLifecycle)
            }

        default:
            Logger.warning("⚠️ Unknown URL host: \(url.host ?? "nil")", category: .appLifecycle)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let captureJobFromURL = Notification.Name("captureJobFromURL")
    // Relay notification sent after sheet is shown, so the view can receive it
    static let captureJobURLReady = Notification.Name("captureJobURLReady")
    static let showDebugLogs = Notification.Name("showDebugLogs")
    static let showSeedGeneration = Notification.Name("showSeedGeneration")
}
