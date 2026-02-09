//
//  AppSheets.swift
//  Sprung
//
import Foundation
import SwiftUI
/// Centralized sheet and UI state management for the main app window
/// Replaces individual Bool bindings with a single organized struct
struct AppSheets {
    var showApplicationReview = false
    var showResumeReview = false
    var showClarifyingQuestions = false
    var showChooseBestCoverLetter = false
    var showMultiModelChooseBest = false
    var showBatchCoverLetter = false
    var showNewJobApp = false
    var showCreateResume = false
    // UI state that was previously in ResumeButtons
    var showResumeInspector = false
    var showCoverLetterInspector = false
    // Unified reference browser (replaces separate Knowledge and Writing browsers)
    var showUnifiedReferenceBrowser = false
    var unifiedBrowserInitialTab: UnifiedReferenceBrowserOverlay.Tab = .knowledge
    // Legacy properties (kept for backwards compatibility during transition)
    var showKnowledgeCardsBrowser: Bool {
        get { showUnifiedReferenceBrowser && unifiedBrowserInitialTab == .knowledge }
        set {
            if newValue {
                unifiedBrowserInitialTab = .knowledge
                showUnifiedReferenceBrowser = true
            } else {
                showUnifiedReferenceBrowser = false
            }
        }
    }
    // Writing context browser (CoverRefs: dossier + writing samples + background facts)
    var showWritingContextBrowser: Bool {
        get { showUnifiedReferenceBrowser && unifiedBrowserInitialTab == .writing }
        set {
            if newValue {
                unifiedBrowserInitialTab = .writing
                showUnifiedReferenceBrowser = true
            } else {
                showUnifiedReferenceBrowser = false
            }
        }
    }
    // Title Sets browser
    var showTitleSetsBrowser: Bool {
        get { showUnifiedReferenceBrowser && unifiedBrowserInitialTab == .titleSets }
        set {
            if newValue {
                unifiedBrowserInitialTab = .titleSets
                showUnifiedReferenceBrowser = true
            } else {
                showUnifiedReferenceBrowser = false
            }
        }
    }
    // Setup wizard (first-run configuration)
    var showSetupWizard = false
    // Job capture from URL scheme (sprung://capture-job?url=...)
    var capturedJobURL: String?
}
// MARK: - Sheet Presentation ViewModifier
struct AppSheetsModifier: ViewModifier {
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]
    @Binding var refPopup: Bool
    @Environment(JobAppStore.self) private var jobAppStore
    @Environment(ResStore.self) private var resStore
    @Environment(CoverLetterStore.self) private var coverLetterStore
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(AppState.self) private var appState
    @Environment(ResumeReviseViewModel.self) private var resumeReviseViewModel
    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore
    @Environment(CoverRefStore.self) private var coverRefStore
    @Environment(SkillStore.self) private var skillStore
    @Environment(CandidateDossierStore.self) private var candidateDossierStore
    @Environment(TitleSetStore.self) private var titleSetStore
    @Environment(LLMFacade.self) private var llmFacade
    @State private var showReprocessConfirmation = false
    @State private var newlyAddedCardName: String = ""
    private var parallelReviewQueueBinding: Binding<Bool> {
        Binding(
            get: { resumeReviseViewModel.showParallelReviewQueueSheet },
            set: { newValue in
                resumeReviseViewModel.showParallelReviewQueueSheet = newValue
            }
        )
    }
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $sheets.showNewJobApp, onDismiss: {
                // Clear captured URL when sheet closes
                sheets.capturedJobURL = nil
            }) {
                NewAppSheetView(
                    isPresented: $sheets.showNewJobApp,
                    initialURL: sheets.capturedJobURL
                )
                .environment(jobAppStore)
                .id(sheets.capturedJobURL ?? "default")
            }
            .onReceive(NotificationCenter.default.publisher(for: .captureJobFromURL)) { notification in
                if let urlString = notification.userInfo?["url"] as? String {
                    Logger.info("📥 [AppSheets] Received job capture URL: \(urlString)", category: .ui)
                    sheets.capturedJobURL = urlString
                    // Show sheet first
                    DispatchQueue.main.async {
                        sheets.showNewJobApp = true
                        // Relay notification after sheet has time to mount and subscribe
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            Logger.info("📤 [AppSheets] Posting captureJobURLReady relay notification", category: .ui)
                            NotificationCenter.default.post(
                                name: .captureJobURLReady,
                                object: nil,
                                userInfo: ["url": urlString]
                            )
                        }
                    }
                }
            }
            .sheet(isPresented: $sheets.showCreateResume) {
                if let selApp = jobAppStore.selectedApp {
                    CreateResumeView(
                        onCreateResume: { template, sources in
                            _ = resStore.create(jobApp: selApp, sources: sources, template: template)
                        }
                    )
                    .padding()
                } else {
                    VStack(spacing: 12) {
                        Text("Select a job application first")
                            .font(.headline)
                        Text("Create Resume is scoped to a specific job application.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Close") {
                            sheets.showCreateResume = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(minWidth: 420, minHeight: 220)
                    .padding()
                }
            }
            .sheet(isPresented: $sheets.showResumeReview) {
                if let selectedResume = jobAppStore.selectedApp?.selectedRes {
                    ResumeReviewSheet(selectedResume: .constant(selectedResume))
                }
            }
            .sheet(isPresented: $sheets.showMultiModelChooseBest) {
                if jobAppStore.selectedApp != nil,
                   let currentCoverLetter = coverLetterStore.cL {
                    MultiModelChooseBestCoverLetterSheet(coverLetter: .constant(currentCoverLetter))
                }
            }
            .sheet(isPresented: $sheets.showApplicationReview) {
                if let selApp = jobAppStore.selectedApp,
                   let currentResume = selApp.selectedRes,
                   let currentCoverLetter = selApp.selectedCover,
                   currentCoverLetter.generated {
                    ApplicationReviewSheet(
                        jobApp: selApp,
                        resume: currentResume,
                        availableCoverLetters: selApp.coverLetters.filter { $0.generated }.sorted { $0.moddedDate > $1.moddedDate }
                    )
                }
            }
            .sheet(isPresented: $sheets.showBatchCoverLetter) {
                BatchCoverLetterView()
                    .environment(appState)
                    .environment(jobAppStore)
                    .environment(coverLetterStore)
                    .environment(enabledLLMStore)
            }
            .sheet(isPresented: $refPopup) {
                ResRefView()
                    .padding()
            }
            .sheet(isPresented: $sheets.showUnifiedReferenceBrowser) {
                UnifiedReferenceBrowserOverlay(
                    isPresented: $sheets.showUnifiedReferenceBrowser,
                    initialTab: sheets.unifiedBrowserInitialTab,
                    knowledgeCards: .init(
                        get: { knowledgeCardStore.knowledgeCards },
                        set: { _ in }
                    ),
                    knowledgeCardStore: knowledgeCardStore,
                    onKnowledgeCardUpdated: { card in
                        knowledgeCardStore.update(card)
                    },
                    onKnowledgeCardDeleted: { card in
                        knowledgeCardStore.delete(card)
                    },
                    onKnowledgeCardAdded: { card in
                        knowledgeCardStore.add(card)
                        // Check if there are active jobs to reprocess
                        let activeStatuses: [Statuses] = [.new, .queued, .inProgress]
                        let activeJobCount = jobAppStore.jobApps.filter { job in
                            !job.jobDescription.isEmpty && activeStatuses.contains(job.status)
                        }.count
                        if activeJobCount > 0 {
                            newlyAddedCardName = card.title
                            showReprocessConfirmation = true
                        }
                    },
                    writingSamples: .init(
                        get: { coverRefStore.storedCoverRefs },
                        set: { _ in }
                    ),
                    onWritingSampleUpdated: { ref in
                        // SwiftData auto-updates
                    },
                    onWritingSampleDeleted: { ref in
                        coverRefStore.deleteCoverRef(ref)
                    },
                    onWritingSampleAdded: { ref in
                        coverRefStore.addCoverRef(ref)
                    },
                    skillStore: skillStore,
                    dossierStore: candidateDossierStore,
                    titleSetStore: titleSetStore,
                    llmFacade: llmFacade
                )
            }
            .alert("Re-run Job Pre-processing?", isPresented: $showReprocessConfirmation) {
                Button("Re-process All") {
                    let count = jobAppStore.rerunPreprocessingForActiveJobs()
                    Logger.info("🔄 [AppSheets] Queued \(count) active jobs for reprocessing after KC addition", category: .ai)
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                let activeStatuses: [Statuses] = [.new, .queued, .inProgress]
                let activeJobCount = jobAppStore.jobApps.filter { job in
                    !job.jobDescription.isEmpty && activeStatuses.contains(job.status)
                }.count
                Text("You added \"\(newlyAddedCardName)\" to your knowledge cards. Would you like to re-run pre-processing for \(activeJobCount) active job\(activeJobCount == 1 ? "" : "s") to match them with relevant cards?")
            }
            .sheet(isPresented: $sheets.showSetupWizard) {
                SetupWizardView {
                    sheets.showSetupWizard = false
                }
            }
            .sheet(isPresented: parallelReviewQueueBinding) {
                ParallelReviewQueueSheetContent(
                    resumeReviseViewModel: resumeReviseViewModel,
                    selectedResume: jobAppStore.selectedApp?.selectedRes
                )
            }
    }
}
// MARK: - Parallel Review Queue Sheet Content
/// Wrapper view for the parallel customization review queue
private struct ParallelReviewQueueSheetContent: View {
    @Bindable var resumeReviseViewModel: ResumeReviseViewModel
    let selectedResume: Resume?
    @Environment(\.modelContext) private var modelContext
    @Environment(ReasoningStreamManager.self) private var reasoningStreamManager
    @State private var showDiscardConfirmation = false

    var body: some View {
        ZStack {
            if let _ = selectedResume,
               let reviewQueue = resumeReviseViewModel.parallelReviewQueue {
                CustomizationReviewQueueView(
                    reviewQueue: reviewQueue,
                    phaseNumber: resumeReviseViewModel.currentPhaseNumber,
                    totalPhases: resumeReviseViewModel.totalPhases,
                    onComplete: {
                        guard let resume = selectedResume else { return }
                        Task {
                            do {
                                try await resumeReviseViewModel.completeCurrentPhaseAndAdvance(
                                    resume: resume,
                                    context: modelContext
                                )
                            } catch {
                                Logger.error("Failed to complete phase: \(error.localizedDescription)")
                            }
                        }
                    },
                    onCancel: {
                        if resumeReviseViewModel.hasUnappliedParallelApprovedChanges() {
                            showDiscardConfirmation = true
                        } else {
                            resumeReviseViewModel.discardParallelChangesAndClose()
                        }
                    }
                )
                .frame(minWidth: 900, minHeight: 600)
            } else {
                VStack(spacing: 12) {
                    if selectedResume == nil {
                        Text("Error: Missing resume")
                    } else {
                        Text("No items to review")
                    }
                    Button("Close") {
                        resumeReviseViewModel.discardParallelChangesAndClose()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(width: 400, height: 300)
            }
        }
        // Reasoning stream as sheet-level overlay
        .overlay {
            if reasoningStreamManager.isVisible {
                ReasoningStreamView(
                    isVisible: Binding(
                        get: { reasoningStreamManager.isVisible },
                        set: { reasoningStreamManager.isVisible = $0 }
                    ),
                    reasoningText: Binding(
                        get: { reasoningStreamManager.reasoningText },
                        set: { reasoningStreamManager.reasoningText = $0 }
                    ),
                    isStreaming: Binding(
                        get: { reasoningStreamManager.isStreaming },
                        set: { reasoningStreamManager.isStreaming = $0 }
                    ),
                    errorMessage: Binding(
                        get: { reasoningStreamManager.errorMessage },
                        set: { reasoningStreamManager.errorMessage = $0 }
                    ),
                    modelName: reasoningStreamManager.modelName
                )
            }
        }
        .confirmationDialog(
            "Cancel Review?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply Approved & Close") {
                guard let resume = selectedResume else { return }
                resumeReviseViewModel.applyApprovedParallelChangesAndClose(
                    resume: resume,
                    context: modelContext
                )
            }
            Button("Discard All", role: .destructive) {
                resumeReviseViewModel.discardParallelChangesAndClose()
            }
            Button("Continue Review", role: .cancel) { }
        } message: {
            Text("You have approved changes that haven't been applied yet.")
        }
    }
}

// MARK: - Helper View Extension
extension View {
    func appSheets(sheets: Binding<AppSheets>, clarifyingQuestions: Binding<[ClarifyingQuestion]>, refPopup: Binding<Bool>) -> some View {
        self.modifier(AppSheetsModifier(sheets: sheets, clarifyingQuestions: clarifyingQuestions, refPopup: refPopup))
    }
}
