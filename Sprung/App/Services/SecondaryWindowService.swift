//
//  SecondaryWindowService.swift
//  Sprung
//
//  Owns the lifetime and presentation of all secondary NSWindow instances.
//  Extracted from AppDelegate to give each window a single, focused home.
//
import Cocoa
import SwiftData
import SwiftUI

// MARK: - Window Spec

/// Declarative chrome for a standard secondary window. The content view is
/// supplied separately so `makeWindow(_:content:observeClose:)` can stay generic
/// — it owns the NSWindow boilerplate every `show*` method used to repeat
/// (contentRect / styleMask / backing, title, tabbing, release policy, center).
private struct WindowSpec {
    var title: String
    var width: CGFloat
    var height: CGFloat
    var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    var minSize: NSSize?
    var disallowTabbing: Bool = false
}

@Observable
@MainActor
final class SecondaryWindowService {
    // MARK: - Window References

    var settingsWindow: NSWindow?
    var applicantProfileWindow: NSWindow?
    var templateEditorWindow: NSWindow?
    var onboardingInterviewWindow: NSWindow?
    var experienceEditorWindow: NSWindow?
    var debugLogsWindow: NSWindow?
    var seedGenerationWindow: NSWindow?
    var resumeRevisionWindow: NSWindow?
    var backgroundActivityWindow: NSWindow?

    // MARK: - Resume Revision Session State

    /// Live agent for the current revision session. The hosting view owns the
    /// agent; this weak handle exists so window teardown can cancel it.
    private weak var activeRevisionAgent: ResumeRevisionAgent?
    /// Resume targeted by the live revision session, used to detect when
    /// Customize is invoked for a different resume than the open window serves.
    private weak var activeRevisionResume: Resume?

    // MARK: - Dependencies

    /// The single composition root, configured once from `SprungApp.onAppear`
    /// (`configure(deps:)`). The manager is constructed in `AppDelegate` before
    /// dependencies exist, so this is nil until that one-shot hand-off — every
    /// `show*` method guards it and logs+returns if a window is somehow requested
    /// before the app finished wiring (rather than presenting a degraded window).
    private(set) var deps: AppDependencies?

    /// One-shot dependency hand-off from the SwiftUI scene once the composition
    /// root exists.
    func configure(deps: AppDependencies) {
        self.deps = deps
    }

    // MARK: - Generic Window Construction

    /// Build a standard secondary NSWindow from a spec + content view, applying
    /// the shared lifecycle policy (centered, not released on close, optional
    /// close observation). Special windows (the borderless onboarding overlay)
    /// build their own NSWindow and do not route through here.
    private func makeWindow(_ spec: WindowSpec, content: NSView, observeClose: Bool = false) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: spec.width, height: spec.height),
            styleMask: spec.styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = spec.title
        if spec.disallowTabbing { window.tabbingMode = .disallowed }
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.center()
        if let minSize = spec.minSize { window.minSize = minSize }
        if observeClose {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }
        return window
    }

    /// Host a secondary-window root with the shared `ToastCenter` overlay mounted.
    /// A main-window toast overlay does not cover separate NSWindows, so every
    /// secondary window routes its content through here to make
    /// `ToastCenter.shared.show(...)` render in whatever window is active. The
    /// debug-logs window mounts its own overlay (`EventDumpView`) and is the one
    /// caller intentionally left off this path to avoid a double overlay.
    private func toastHosted<Content: View>(_ root: Content) -> NSHostingView<AnyView> {
        NSHostingView(rootView: AnyView(root.toastOverlay()))
    }

    // MARK: - Settings Window

    func showSettings() {
        presentSettings(initialCategory: nil, highlightModelKey: nil)
    }

    /// Open Settings on the Models tab with the row for `highlightKey` boxed in red.
    /// `highlightKey` is a UserDefaults model-setting key (e.g. the value carried by
    /// `ModelConfigurationError.settingKey`); pass nil to just land on the Models tab.
    func showModelSettings(highlightKey: String?) {
        presentSettings(initialCategory: .models, highlightModelKey: highlightKey)
    }

    private func presentSettings(initialCategory: SettingsCategory?, highlightModelKey: String?) {
        guard let deps else {
            Logger.warning("Settings window requested before app services were configured", category: .appLifecycle)
            return
        }
        let isNewWindow = (settingsWindow == nil)
        if isNewWindow {
            let appEnvironment = deps.appEnvironment
            let appState = appEnvironment.appState
            let debugSettingsStore = appState.debugSettingsStore ?? appEnvironment.debugSettingsStore
            let root = SettingsView(
                initialCategory: initialCategory ?? .apiKeys,
                initialHighlightModelKey: highlightModelKey
            )
                .environment(appEnvironment)
                .environment(appState)
                .environment(appEnvironment.navigationState)
                .environment(appEnvironment.onboardingCoordinator)
                .environment(appEnvironment.llmFacade)
                .environment(deps.enabledLLMStore)
                .environment(deps.applicantProfileStore)
                .environment(deps.experienceDefaultsStore)
                .environment(deps.careerKeywordStore)
                .environment(deps.guidanceStore)
                .environment(appEnvironment.openRouterService)
                .environment(debugSettingsStore)
                .environment(deps.searchOpsCoordinator)
                .environment(deps.skillStore)
                .environment(deps.jobAppStore)
                .environment(deps.titleSetStore)
                .modelContainer(deps.modelContainer)
            settingsWindow = makeWindow(
                WindowSpec(title: "Settings", width: 400, height: 200, styleMask: [.titled, .closable]),
                content: toastHosted(root)
            )
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // A freshly-built SettingsView receives its target via init; an existing one
        // (window persists across close) is driven live with this notification.
        if !isNewWindow, initialCategory != nil {
            NotificationCenter.default.post(
                name: .highlightModelSetting,
                object: nil,
                userInfo: highlightModelKey.map { ["settingKey": $0] }
            )
        }
    }

    // MARK: - Applicant Profile Window

    func showApplicantProfile() {
        guard let deps else {
            Logger.warning("Applicant Profile window requested before app services were configured", category: .appLifecycle)
            return
        }
        if let window = applicantProfileWindow, !window.isVisible {
            applicantProfileWindow = nil
        }
        if applicantProfileWindow == nil {
            let appEnvironment = deps.appEnvironment
            let root = ApplicantProfileView()
                .environment(appEnvironment)
                .environment(appEnvironment.appState)
                .environment(deps.applicantProfileStore)
                .environment(appEnvironment.experienceDefaultsStore)
                .environment(appEnvironment.careerKeywordStore)
                .environment(deps.guidanceStore)
                .modelContainer(deps.modelContainer)
            applicantProfileWindow = makeWindow(
                WindowSpec(
                    title: "Applicant Profile", width: 600, height: 650,
                    minSize: NSSize(width: 500, height: 520)
                ),
                content: toastHosted(root),
                observeClose: true
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
            // Single teardown choke point for the revision session: every close
            // path (title-bar close, in-view Cancel/Close, window replacement
            // for a different resume) lands here and cancels the live agent
            // exactly once. cancel() is idempotent and continuation-safe.
            activeRevisionAgent?.cancel()
            activeRevisionAgent = nil
            activeRevisionResume = nil
            resumeRevisionWindow = nil
        }
    }

    // MARK: - Template Editor Window

    func showTemplateEditor() {
        guard let deps else {
            Logger.warning("Template Editor window requested before app services were configured", category: .appLifecycle)
            return
        }
        if let window = templateEditorWindow, !window.isVisible {
            templateEditorWindow = nil
        }
        if templateEditorWindow == nil {
            let appEnvironment = deps.appEnvironment
            let root = TemplateEditorView()
                .modelContainer(deps.modelContainer)
                .environment(appEnvironment)
                .environment(appEnvironment.appState)
                .environment(appEnvironment.navigationState)
                .environment(deps.jobAppStore)
                .environment(appEnvironment.experienceDefaultsStore)
                .environment(appEnvironment.careerKeywordStore)
                .environment(appEnvironment.applicantProfileStore)
                .environment(deps.guidanceStore)
            templateEditorWindow = makeWindow(
                WindowSpec(
                    title: "Template Editor", width: 1200, height: 760,
                    minSize: NSSize(width: 960, height: 640), disallowTabbing: true
                ),
                content: toastHosted(root)
            )
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
        guard let deps else {
            Logger.error("Onboarding interview window requested before app services were configured", category: .ui)
            return
        }
        var shouldAnimatePresentation = false
        if let window = onboardingInterviewWindow, !window.isVisible {
            onboardingInterviewWindow = nil
            shouldAnimatePresentation = true
        }
        if onboardingInterviewWindow == nil {
            let appEnvironment = deps.appEnvironment
            let onboardingService = deps.onboardingCoordinator
            let debugSettingsStore = appEnvironment.appState.debugSettingsStore ?? appEnvironment.debugSettingsStore
            let root = OnboardingInterviewView()
                .modelContainer(deps.modelContainer)
                .environment(appEnvironment)
                .environment(appEnvironment.appState)
                .environment(appEnvironment.navigationState)
                .environment(deps.enabledLLMStore)
                .environment(deps.coverRefStore)
                .environment(appEnvironment.applicantProfileStore)
                .environment(appEnvironment.experienceDefaultsStore)
                .environment(deps.guidanceStore)
                .environment(onboardingService)
                .environment(onboardingService.toolRouter)
                .environment(debugSettingsStore)
            let hostingView = toastHosted(root)
            let innerXPadding: CGFloat = 32 * 2        // = 64
            let minCardWidth = 1040 + innerXPadding    // = 1104
            let outerPad: CGFloat = 30                 // same as shadowR (left/right)
            let windowW = minCardWidth + outerPad * 2  // = 1164
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

    // MARK: - Experience Editor Window

    func showExperienceEditor() {
        guard let deps else {
            Logger.warning("Experience Editor window requested before app services were configured", category: .appLifecycle)
            return
        }
        if let window = experienceEditorWindow, !window.isVisible {
            experienceEditorWindow = nil
        }
        if experienceEditorWindow == nil {
            let appEnvironment = deps.appEnvironment
            let root = ExperienceEditorView()
                .modelContainer(deps.modelContainer)
                .environment(appEnvironment)
                .environment(appEnvironment.appState)
                .environment(deps.experienceDefaultsStore)
                .environment(appEnvironment.careerKeywordStore)
                .environment(deps.guidanceStore)
                .environment(deps.experienceEntryRefinementService)
            experienceEditorWindow = makeWindow(
                WindowSpec(
                    title: "Experience Editor", width: 1180, height: 780,
                    minSize: NSSize(width: 960, height: 680), disallowTabbing: true
                ),
                content: toastHosted(root),
                observeClose: true
            )
        }
        experienceEditorWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Resume Revision Window

    /// Single, module-independent choke point for the Customize entry.
    /// All entry paths (menu ⌘R, toolbar button, editor drawer button) post
    /// `.customizeResume`, which AppDelegate routes here. Gating and session
    /// identity checks live here and nowhere else.
    func showResumeRevision() {
        guard let deps else {
            Logger.warning("Resume revision requested before app services were configured", category: .ui)
            return
        }
        guard let selectedResume = deps.jobAppStore.selectedApp?.selectedRes else {
            presentRevisionGuidanceAlert(
                title: "No Resume Selected",
                message: "Select a job application with a resume before starting a Customize session."
            )
            return
        }
        guard selectedResume.hasUpdatableNodes else {
            presentRevisionGuidanceAlert(
                title: "Nothing Marked for AI Revision",
                message: "Mark the sections, entries, or fields you want the agent to revise (AI status icons in the resume editor) before starting a Customize session."
            )
            return
        }

        // Reuse the open window only when it still serves the selected resume.
        // Otherwise close it — windowWillClose cancels the old agent — and
        // start a fresh session for the new target.
        if let window = resumeRevisionWindow {
            if activeRevisionResume === selectedResume {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            window.close()
        }

        let appEnvironment = deps.appEnvironment
        let revisionView = ResumeRevisionView(
            resume: selectedResume,
            onAgentCreated: { [weak self, weak selectedResume] agent in
                // The view creates its agent asynchronously (after an awaited
                // PDF render), so a replaced window's view could register late.
                // Only accept the registration while this session is still the
                // active one; a stale view's agent is torn down by its own
                // task cancellation (run() honors Task.isCancelled).
                guard let self, let selectedResume,
                      self.activeRevisionResume === selectedResume else { return }
                self.activeRevisionAgent = agent
            },
            onRequestClose: { [weak self] in
                self?.resumeRevisionWindow?.close()
            }
        )
        let root = revisionView
            .modelContainer(deps.modelContainer)
            .environment(appEnvironment.llmFacade)
            .environment(deps.templateStore)
            .environment(appEnvironment.applicantProfileStore)
            .environment(deps.knowledgeCardStore)
            .environment(deps.skillStore)
            .environment(deps.coverRefStore)
            .environment(deps.titleSetStore)
            .environment(deps.guidanceStore)
            .environment(deps.candidateDossierStore)

        let window = makeWindow(
            WindowSpec(
                title: revisionWindowTitle(for: selectedResume), width: 1300, height: 800,
                minSize: NSSize(width: 1100, height: 650), disallowTabbing: true
            ),
            content: toastHosted(root),
            observeClose: true
        )

        resumeRevisionWindow = window
        activeRevisionResume = selectedResume
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Title identifying the revision session by job position and company.
    private func revisionWindowTitle(for resume: Resume) -> String {
        guard let jobApp = resume.jobApp else { return "Customize Resume" }
        let position = jobApp.jobPosition.trimmingCharacters(in: .whitespacesAndNewlines)
        let company = jobApp.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (position.isEmpty, company.isEmpty) {
        case (false, false): return "Customize Resume — \(position) at \(company)"
        case (false, true): return "Customize Resume — \(position)"
        case (true, false): return "Customize Resume — \(company)"
        case (true, true): return "Customize Resume"
        }
    }

    private func presentRevisionGuidanceAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Debug Logs Window

    func showDebugLogs(coordinator: OnboardingInterviewCoordinator) {
        Logger.info("showDebugLogsWindow called", category: .ui)
        if let window = debugLogsWindow, !window.isVisible {
            debugLogsWindow = nil
        }
        if debugLogsWindow == nil {
            Logger.info("Creating debug logs window", category: .ui)
            debugLogsWindow = makeWindow(
                WindowSpec(
                    title: "Debug Logs", width: 800, height: 600,
                    minSize: NSSize(width: 600, height: 400)
                ),
                content: NSHostingView(rootView: EventDumpView(coordinator: coordinator))
            )
        }
        debugLogsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Seed Generation Window

    func showSeedGeneration() async {
        Logger.info("showSeedGenerationWindow called", category: .ui)
        guard let deps else {
            Logger.error("Cannot show seed generation: app services not configured", category: .ui)
            return
        }

        // Reset window if it was closed
        if let window = seedGenerationWindow, !window.isVisible {
            seedGenerationWindow = nil
        }

        if seedGenerationWindow == nil {
            let appEnvironment = deps.appEnvironment

            // Prerequisite: at least one knowledge card to generate from. Without any,
            // generation has no source material — surface the paths to create some
            // instead of failing silently.
            guard !deps.knowledgeCardStore.knowledgeCards.isEmpty else {
                Logger.error("Cannot show seed generation: no knowledge cards exist.", category: .ui)
                presentNoKnowledgeCardsAlert()
                return
            }

            // Build SeedGenerationContext from onboarding artifacts
            guard let context = await SeedGenerationContextBuilder.build(
                knowledgeCardStore: deps.knowledgeCardStore,
                skillStore: deps.skillStore,
                experienceDefaultsStore: deps.experienceDefaultsStore,
                applicantProfileStore: deps.applicantProfileStore,
                coverRefStore: deps.coverRefStore,
                candidateDossierStore: deps.candidateDossierStore,
                titleSetStore: deps.titleSetStore
            ) else {
                Logger.error("Failed to build SeedGenerationContext", category: .ui)
                presentContextBuildFailureAlert()
                return
            }

            // Get model and backend from settings (per-backend model persistence).
            // No silent backend default — an unconfigured backend surfaces the picker.
            guard let backendString = UserDefaults.standard.string(forKey: "seedGenerationBackend"),
                  !backendString.isEmpty else {
                Logger.error("Cannot show seed generation: no backend configured.", category: .ui)
                presentSeedModelAlert(
                    message: "Choose a backend and model for Experience Defaults generation before continuing.",
                    highlightKey: "seedGenerationBackend"
                )
                return
            }
            let backend: LLMFacade.Backend = backendString == "anthropic" ? .anthropic : .openRouter
            let modelKey = backendString == "anthropic" ? "seedGenerationAnthropicModelId" : "seedGenerationOpenRouterModelId"
            guard let modelId = UserDefaults.standard.string(forKey: modelKey),
                  !modelId.isEmpty else {
                Logger.error("Cannot show seed generation: no model configured.", category: .ui)
                presentSeedModelAlert(
                    message: "Select \(backend == .anthropic ? "an Anthropic" : "an OpenRouter") model for Experience Defaults generation before continuing.",
                    highlightKey: modelKey
                )
                return
            }

            let orchestrator = SeedGenerationOrchestrator(
                context: context,
                llmFacade: appEnvironment.llmFacade,
                modelId: modelId,
                backend: backend,
                experienceDefaultsStore: deps.experienceDefaultsStore
            )

            let root = SeedGenerationView(orchestrator: orchestrator)
                .modelContainer(deps.modelContainer)
                .environment(appEnvironment)
                .environment(appEnvironment.appState)
                .environment(appEnvironment.llmFacade)
                .environment(deps.experienceDefaultsStore)
                .environment(deps.guidanceStore)
                .environment(deps.titleSetStore)
            seedGenerationWindow = makeWindow(
                WindowSpec(
                    title: "Seed Generation", width: 1000, height: 700,
                    minSize: NSSize(width: 800, height: 600), disallowTabbing: true
                ),
                content: toastHosted(root)
            )
            Logger.info("Created seed generation window", category: .ui)
        }

        seedGenerationWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Missing backend/model for Experience Defaults: explain, then route to the
    /// Models settings tab with the unconfigured picker boxed in red.
    private func presentSeedModelAlert(message: String, highlightKey: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Model Required for Experience Defaults"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Model Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            showModelSettings(highlightKey: highlightKey)
        }
    }

    /// No knowledge cards to generate from: offer the two ways to create some
    /// (onboarding interview, or the Knowledge Card browser) or cancel.
    private func presentNoKnowledgeCardsAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "No Knowledge Cards Yet"
        alert.informativeText = "Experience Defaults are generated from your knowledge cards, but none exist yet. Run the onboarding interview to build them from your documents, or add cards manually in the Knowledge Card browser."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start Onboarding Interview")
        alert.addButton(withTitle: "Open Knowledge Card Browser")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            showOnboardingInterview()
        case .alertSecondButtonReturn:
            openKnowledgeCardBrowser()
        default:
            break
        }
    }

    /// SeedGenerationContextBuilder returned nil — onboarding likely incomplete.
    private func presentContextBuildFailureAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't Assemble Generation Context"
        alert.informativeText = "Couldn't assemble generation context. Ensure the onboarding interview has been completed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Bring the main window's References module forward on the Knowledge tab.
    private func openKnowledgeCardBrowser() {
        NotificationCenter.default.post(
            name: .navigateToModule, object: nil,
            userInfo: ["module": AppModule.references.rawValue]
        )
        NotificationCenter.default.post(
            name: .navigateToReferencesTab, object: nil,
            userInfo: ["tab": ReferencesModuleView.Tab.knowledge.rawValue]
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Background Activity Window

    func showBackgroundActivity() {
        if let window = backgroundActivityWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let tracker = deps?.backgroundActivityTracker else {
            Logger.warning("Background activity tracker not configured", category: .appLifecycle)
            return
        }

        let window = makeWindow(
            WindowSpec(
                title: "Background Activity", width: 700, height: 450,
                minSize: NSSize(width: 500, height: 300)
            ),
            content: toastHosted(BackgroundActivityContent(tracker: tracker))
        )
        backgroundActivityWindow = window
        window.makeKeyAndOrderFront(nil)
    }
}
