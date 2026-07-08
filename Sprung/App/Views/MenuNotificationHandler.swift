// Sprung/App/Views/MenuNotificationHandler.swift
import SwiftUI
import Foundation
import AppKit
/// Handles menu command notifications and delegates to appropriate UI actions.
/// 
/// ## Architecture Note
/// macOS menu and toolbar commands originate in AppKit and cannot access SwiftUI
/// bindings directly. We intentionally use `NotificationCenter` here as a bridge
/// between those command sources and the SwiftUI view hierarchy. Only the
/// notifications listed in `MenuCommands.swift` should be observed, and they map
/// 1:1 with menu or toolbar items. View-local interactions should prefer SwiftUI
/// bindings rather than introducing new notifications.
/// Lives at the shell level (`UnifiedAppLayout`), NOT inside any module view,
/// so every menu/toolbar command works regardless of which module is frontmost.
/// Commands whose final observers live inside the Resume Editor module's view
/// tree navigate there first (`ModuleNavigationService`) before acting — the
/// same navigate-then-trigger pattern the Discovery menu uses.
@Observable
class MenuNotificationHandler {
    private weak var jobAppStore: JobAppStore?
    private weak var coverLetterStore: CoverLetterStore?
    private weak var moduleNavigation: ModuleNavigationService?
    private var sheets: Binding<AppSheets>?
    private var selectedTab: Binding<TabList>?
    private var observersConfigured = false
    init() {}
    /// Setup the handler with required dependencies
    func configure(
        jobAppStore: JobAppStore,
        coverLetterStore: CoverLetterStore,
        moduleNavigation: ModuleNavigationService,
        sheets: Binding<AppSheets>,
        selectedTab: Binding<TabList>
    ) {
        Logger.info("🛠️ MenuNotificationHandler configure invoked", category: .ui)
        self.jobAppStore = jobAppStore
        self.coverLetterStore = coverLetterStore
        self.moduleNavigation = moduleNavigation
        self.sheets = sheets
        self.selectedTab = selectedTab
        guard !observersConfigured else {
            Logger.debug("♻️ MenuNotificationHandler already configured; skipping observer setup", category: .ui)
            return
        }
        observersConfigured = true
        Logger.debug("✅ MenuNotificationHandler registering NotificationCenter observers", category: .ui)
        setupNotificationObservers()
    }
    private func setupNotificationObservers() {
        // Job Application Commands
        NotificationCenter.default.addObserver(
            forName: .newJobApp,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showNewJobApp = true
        }
        NotificationCenter.default.addObserver(
            forName: .manualJobAppCreated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Surface the Resume Editor's listing tab for manual entry editing
            Task { @MainActor in
                self?.showResumeEditor(tab: .listing)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .bestJob,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleBestJob()
            }
        }
        // Resume Commands
        // .customizeResume opens the revision window via AppDelegate (the
        // module-independent choke point). This observer only syncs the Resume
        // Editor's tab state so the resume is visible next time that module is up.
        NotificationCenter.default.addObserver(
            forName: .customizeResume,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.selectedTab?.wrappedValue = .resume
            }
        }
        NotificationCenter.default.addObserver(
            forName: .optimizeResume,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showResumeReview = true
        }
        // Cover Letter Commands
        NotificationCenter.default.addObserver(
            forName: .generateCoverLetter,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleGenerateCoverLetter()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .reviseCoverLetter,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleReviseCoverLetter()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .batchCoverLetter,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showBatchCoverLetter = true
        }
        NotificationCenter.default.addObserver(
            forName: .bestCoverLetter,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleBestCoverLetter()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .committee,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showMultiModelChooseBest = true
        }
        NotificationCenter.default.addObserver(
            forName: .showCoverLetterInspector,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showResumeEditor(tab: .coverLetter)
                self?.sheets?.wrappedValue.showCoverLetterInspector.toggle()
            }
        }
        // Analysis Commands
        NotificationCenter.default.addObserver(
            forName: .analyzeApplication,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showApplicationReview = true
        }
        NotificationCenter.default.addObserver(
            forName: .preprocessAllPendingJobs,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePreprocessAllPendingJobs()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .rerunAllJobPreprocessing,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleRerunAllJobPreprocessing()
            }
        }
        // Text-to-Speech Commands
        NotificationCenter.default.addObserver(
            forName: .startSpeaking,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleStartSpeaking()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .stopSpeaking,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleStopSpeaking()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .restartSpeaking,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleRestartSpeaking()
            }
        }
        // Window-level commands (.showSettings, .startOnboardingInterview) are
        // now observed directly by AppDelegate so they work regardless of which
        // module is active.
        // Create New Resume
        NotificationCenter.default.addObserver(
            forName: .createNewResume,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showCreateResume = true
        }
        // Setup Wizard: observed by UnifiedAppLayout (the single presenter,
        // which also owns the hasCompletedSetupWizard bookkeeping) — no
        // observer here, so the sheet is never double-presented.
        // Discovery lives in the main-window module shell; its menu items post
        // .navigateToModule (plus module-scoped trigger notifications) directly
        // from SprungApp, so no observers are needed here.
        // Export Commands - surface the Submit tab and relay via .triggerExport
        // (the observer, ResumeExportView, is tab content and must mount first)
        let exportMap: [(Notification.Name, String)] = [
            (.exportResumePDF, "resumePDF"),
            (.exportResumeText, "resumeText"),
            (.exportResumeJSON, "resumeJSON"),
            (.exportCoverLetterPDF, "coverLetterPDF"),
            (.exportCoverLetterText, "coverLetterText"),
            (.exportAllCoverLetters, "allCoverLetters"),
            (.exportApplicationPacket, "completeApplication"),
        ]
        for (name, optionKey) in exportMap {
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.showResumeEditor(tab: .submitApp)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(
                        name: .triggerExport,
                        object: nil,
                        userInfo: ["option": optionKey]
                    )
                }
            }
        }
    }
    // MARK: - Menu Action Handlers
    // These handlers directly trigger the same UI state changes that the toolbar buttons do
    /// Bring the Resume Editor module to front and select a tab. Used by every
    /// command whose observer or result surface lives inside that module's tree.
    @MainActor
    private func showResumeEditor(tab: TabList) {
        moduleNavigation?.selectModule(.resumeEditor)
        selectedTab?.wrappedValue = tab
    }
    @MainActor
    private func handleBestJob() {
        // Trigger the same action as the BestJobButton in the toolbar
        // (headless observer lives at the shell level — works in any module)
        NotificationCenter.default.post(name: .triggerBestJobButton, object: nil)
    }
    @MainActor
    private func handleGenerateCoverLetter() {
        // Surface the cover letter tab first
        showResumeEditor(tab: .coverLetter)
        // Trigger the same action as CoverLetterGenerateButton
        // (headless observer lives at the shell level — no mount race)
        NotificationCenter.default.post(name: .triggerGenerateCoverLetterButton, object: nil)
    }
    @MainActor
    private func handleReviseCoverLetter() {
        // Surface the cover letter tab first — its observer
        // (CoverLetterReviseButton) is tab content and must mount before
        // the trigger fires, hence the delay (same pattern as exports).
        showResumeEditor(tab: .coverLetter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .triggerReviseCoverLetterButton, object: nil)
        }
    }
    @MainActor
    private func handleBestCoverLetter() {
        // Trigger the multi-model choose best cover letter sheet
        // This shows the multi-model choose best cover letter sheet
        guard let jobAppStore = jobAppStore else { return }
        // Check if we have enough cover letters (same logic as toolbar button)
        let generatedLetters = jobAppStore.selectedApp?.coverLetters.filter { $0.generated } ?? []
        if generatedLetters.count < 2 {
            // Show alert - need at least 2 generated letters
            let alert = NSAlert()
            alert.messageText = "Best Cover Letter"
            alert.informativeText = "You need at least 2 generated cover letters to use this feature."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        // Directly trigger the committee/multi-model selection (same as toolbar button)
        sheets?.wrappedValue.showMultiModelChooseBest = true
    }
    @MainActor
    private func handleStartSpeaking() {
        // Surface the cover letter tab, then trigger TTS start once its
        // observer (TTSButton, tab content) has had a chance to mount.
        showResumeEditor(tab: .coverLetter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .triggerTTSStart, object: nil)
        }
    }
    @MainActor
    private func handleStopSpeaking() {
        // Trigger TTS stop (if nothing observes, nothing is speaking)
        NotificationCenter.default.post(name: .triggerTTSStop, object: nil)
    }
    @MainActor
    private func handleRestartSpeaking() {
        // Surface the cover letter tab, then trigger TTS restart (see start)
        showResumeEditor(tab: .coverLetter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .triggerTTSRestart, object: nil)
        }
    }
    @MainActor
    private func handlePreprocessAllPendingJobs() {
        guard let jobAppStore = jobAppStore else { return }
        let count = jobAppStore.preprocessAllPendingJobs()
        if count > 0 {
            Logger.info("🔄 [Menu] Queued \(count) jobs for preprocessing", category: .ai)
        } else {
            Logger.info("✅ [Menu] All jobs already preprocessed", category: .ai)
        }
    }

    @MainActor
    private func handleRerunAllJobPreprocessing() {
        guard let jobAppStore = jobAppStore else { return }
        let count = jobAppStore.rerunPreprocessingForActiveJobs()
        if count > 0 {
            Logger.info("🔄 [Menu] Queued \(count) active jobs for reprocessing", category: .ai)
        } else {
            Logger.info("✅ [Menu] No active jobs to reprocess", category: .ai)
        }
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
