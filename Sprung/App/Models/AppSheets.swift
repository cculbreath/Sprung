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
    private var revisionSheetBinding: Binding<Bool> {
        Binding(
            get: { resumeReviseViewModel.showResumeRevisionSheet },
            set: { newValue in
                resumeReviseViewModel.showResumeRevisionSheet = newValue
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
            .sheet(isPresented: $sheets.showSetupWizard) {
                SetupWizardView {
                    sheets.showSetupWizard = false
                }
            }
            .sheet(isPresented: revisionSheetBinding) {
                if let selectedResume = jobAppStore.selectedApp?.selectedRes {
                    RevisionReviewView(
                        viewModel: resumeReviseViewModel,
                        resume: .constant(selectedResume)
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
