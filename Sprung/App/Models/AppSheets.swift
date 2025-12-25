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
    // Knowledge cards browser
    var showKnowledgeCardsBrowser = false
    // Writing context browser (CoverRefs: dossier + writing samples + background facts)
    var showWritingContextBrowser = false
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
    @Environment(ResRefStore.self) private var resRefStore
    @Environment(CoverRefStore.self) private var coverRefStore
    private var revisionSheetBinding: Binding<Bool> {
        Binding(
            get: { resumeReviseViewModel.showResumeRevisionSheet },
            set: { newValue in
                resumeReviseViewModel.showResumeRevisionSheet = newValue
            }
        )
    }

    private var skillExperiencePickerBinding: Binding<Bool> {
        Binding(
            get: { resumeReviseViewModel.showSkillExperiencePicker },
            set: { newValue in
                resumeReviseViewModel.showSkillExperiencePicker = newValue
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
            .sheet(isPresented: revisionSheetBinding) {
                RevisionReviewSheetContent(
                    resumeReviseViewModel: resumeReviseViewModel,
                    selectedResume: jobAppStore.selectedApp?.selectedRes
                )
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
            .sheet(isPresented: $sheets.showKnowledgeCardsBrowser) {
                KnowledgeCardBrowserOverlay(
                    isPresented: $sheets.showKnowledgeCardsBrowser,
                    cards: .init(
                        get: { resRefStore.resRefs },
                        set: { _ in }
                    ),
                    resRefStore: resRefStore,
                    onCardUpdated: { card in
                        resRefStore.updateResRef(card)
                    },
                    onCardDeleted: { card in
                        resRefStore.deleteResRef(card)
                    },
                    onCardAdded: { card in
                        resRefStore.addResRef(card)
                    }
                )
            }
            .sheet(isPresented: $sheets.showWritingContextBrowser) {
                WritingContextBrowserSheet(isPresented: $sheets.showWritingContextBrowser)
                    .environment(coverRefStore)
            }
            .sheet(isPresented: $sheets.showSetupWizard) {
                SetupWizardView {
                    sheets.showSetupWizard = false
                }
            }
            .sheet(isPresented: skillExperiencePickerBinding) {
                SkillExperiencePickerSheet(
                    skills: resumeReviseViewModel.pendingSkillQueries,
                    onComplete: { results in
                        resumeReviseViewModel.submitSkillExperienceResults(results)
                    },
                    onCancel: {
                        resumeReviseViewModel.cancelSkillExperienceQuery()
                    }
                )
            }
    }
}
// MARK: - Revision Review Sheet Content
/// Wrapper view that includes the reasoning stream overlay inside the sheet
private struct RevisionReviewSheetContent: View {
    @Bindable var resumeReviseViewModel: ResumeReviseViewModel
    let selectedResume: Resume?
    @Environment(ReasoningStreamManager.self) private var reasoningStreamManager

    var body: some View {
        ZStack {
            if let resume = selectedResume {
                RevisionReviewView(
                    viewModel: resumeReviseViewModel,
                    resume: .constant(resume)
                )
                .frame(minWidth: 850)
                .onAppear {
                    Logger.debug(
                        "🔍 [AppSheets] Creating RevisionReviewView with resume: \(resume.id.uuidString)",
                        category: .ui
                    )
                    Logger.debug(
                        "🔍 [AppSheets] ViewModel has \(resumeReviseViewModel.resumeRevisions.count) revisions",
                        category: .ui
                    )
                }
            } else {
                Text("Error: Missing resume")
                    .frame(width: 400, height: 300)
                    .onAppear {
                        Logger.debug("🔍 [AppSheets] Failed to get selectedResume", category: .ui)
                    }
            }
        }
        // Reasoning stream as sheet-level overlay so it appears on top
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
    }
}

// MARK: - Helper View Extension
extension View {
    func appSheets(sheets: Binding<AppSheets>, clarifyingQuestions: Binding<[ClarifyingQuestion]>, refPopup: Binding<Bool>) -> some View {
        self.modifier(AppSheetsModifier(sheets: sheets, clarifyingQuestions: clarifyingQuestions, refPopup: refPopup))
    }
}
