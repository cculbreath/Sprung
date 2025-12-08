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
@Observable
class MenuNotificationHandler {
    private weak var jobAppStore: JobAppStore?
    private weak var coverLetterStore: CoverLetterStore?
    private var sheets: Binding<AppSheets>?
    private var selectedTab: Binding<TabList>?
    private var showSlidingList: Binding<Bool>?
    private var observersConfigured = false
    init() {}
    /// Setup the handler with required dependencies
    func configure(
        jobAppStore: JobAppStore,
        coverLetterStore: CoverLetterStore,
        sheets: Binding<AppSheets>,
        selectedTab: Binding<TabList>,
        showSlidingList: Binding<Bool>
    ) {
        Logger.info("🛠️ MenuNotificationHandler configure invoked", category: .ui)
        self.jobAppStore = jobAppStore
        self.coverLetterStore = coverLetterStore
        self.sheets = sheets
        self.selectedTab = selectedTab
        self.showSlidingList = showSlidingList
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
            forName: .bestJob,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleBestJob()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .toggleKnowledgeCards,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Open the knowledge cards deck browser sheet
            self?.sheets?.wrappedValue.showKnowledgeCardsBrowser = true
        }
        // Resume Commands
        NotificationCenter.default.addObserver(
            forName: .customizeResume,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.selectedTab?.wrappedValue = .resume
                self?.handleCustomizeResume()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .clarifyCustomize,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.selectedTab?.wrappedValue = .resume
                self?.handleClarifyCustomize()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .optimizeResume,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showResumeReview = true
        }
        NotificationCenter.default.addObserver(
            forName: .showResumeInspector,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.selectedTab?.wrappedValue = .resume
            self?.sheets?.wrappedValue.showResumeInspector.toggle()
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
            self?.selectedTab?.wrappedValue = .coverLetter
            self?.sheets?.wrappedValue.showCoverLetterInspector.toggle()
        }
        // Analysis Commands
        NotificationCenter.default.addObserver(
            forName: .analyzeApplication,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showApplicationReview = true
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
        // Window Commands (toolbar buttons that delegate to existing menu commands)
        NotificationCenter.default.addObserver(
            forName: .showSettings,
            object: nil,
            queue: .main
        ) { _ in
            // Delegate to AppDelegate via existing menu command mechanism
            Task { @MainActor in
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    appDelegate.showSettingsWindow()
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: .showApplicantProfile,
            object: nil,
            queue: .main
        ) { _ in
            // Delegate to AppDelegate via existing menu command mechanism
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.showApplicantProfileWindow()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .showTemplateEditor,
            object: nil,
            queue: .main
        ) { _ in
            // Delegate to AppDelegate via existing menu command mechanism
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.showTemplateEditorWindow()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .showExperienceEditor,
            object: nil,
            queue: .main
        ) { _ in
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.showExperienceEditorWindow()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .startOnboardingInterview,
            object: nil,
            queue: .main
        ) { _ in
            Logger.info("📨 Received startOnboardingInterview notification", category: .ui)
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                Logger.debug("🎯 Dispatching to AppDelegate.showOnboardingInterviewWindow", category: .ui)
                Task { @MainActor in
                    appDelegate.showOnboardingInterviewWindow()
                }
            }
        }
    }
    // MARK: - Menu Action Handlers
    // These handlers directly trigger the same UI state changes that the toolbar buttons do
    @MainActor
    private func handleBestJob() {
        // Trigger the same action as the BestJobButton in the toolbar
        NotificationCenter.default.post(name: .triggerBestJobButton, object: nil)
    }
    @MainActor
    private func handleCustomizeResume() {
        // Switch to resume tab first (same as toolbar button does)
        selectedTab?.wrappedValue = .resume
        // Trigger the same action as ResumeCustomizeButton
        NotificationCenter.default.post(name: .triggerCustomizeButton, object: nil)
    }
    @MainActor
    private func handleClarifyCustomize() {
        // Switch to resume tab first
        selectedTab?.wrappedValue = .resume
        // Trigger the same action as ClarifyingQuestionsButton
        NotificationCenter.default.post(name: .triggerClarifyingQuestionsButton, object: nil)
    }
    @MainActor
    private func handleGenerateCoverLetter() {
        // Switch to cover letter tab first
        selectedTab?.wrappedValue = .coverLetter
        // Trigger the same action as CoverLetterGenerateButton
        NotificationCenter.default.post(name: .triggerGenerateCoverLetterButton, object: nil)
    }
    @MainActor
    private func handleReviseCoverLetter() {
        // Switch to cover letter tab first
        selectedTab?.wrappedValue = .coverLetter
        // Trigger the same action as CoverLetterReviseButton
        NotificationCenter.default.post(name: .triggerReviseCoverLetterButton, object: nil)
    }
    @MainActor
    private func handleBestCoverLetter() {
        // Trigger the same action as the "committee" button in UnifiedToolbar
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
        // Switch to cover letter tab and trigger TTS start
        selectedTab?.wrappedValue = .coverLetter
        NotificationCenter.default.post(name: .triggerTTSStart, object: nil)
    }
    @MainActor
    private func handleStopSpeaking() {
        // Trigger TTS stop
        NotificationCenter.default.post(name: .triggerTTSStop, object: nil)
    }
    @MainActor
    private func handleRestartSpeaking() {
        // Switch to cover letter tab and trigger TTS restart
        selectedTab?.wrappedValue = .coverLetter
        NotificationCenter.default.post(name: .triggerTTSRestart, object: nil)
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
