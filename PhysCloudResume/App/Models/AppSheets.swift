//
//  AppSheets.swift
//  PhysCloudResume
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
    
    // UI state that was previously in ResumeButtons
    var showResumeInspector = false
    var showCoverLetterInspector = false
}

// MARK: - Sheet Presentation ViewModifier

struct AppSheetsModifier: ViewModifier {
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]
    @Binding var refPopup: Bool
    
    @Environment(JobAppStore.self) private var jobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore
    @Environment(\.appState) private var appState
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $sheets.showNewJobApp) {
                NewAppSheetView(
                    scrapingDogApiKey: UserDefaults.standard.string(forKey: "scrapingDogApiKey") ?? "none",
                    isPresented: $sheets.showNewJobApp
                )
                .environment(jobAppStore)
            }
            .sheet(isPresented: $sheets.showResumeReview) {
                if let selectedResume = jobAppStore.selectedApp?.selectedRes {
                    ResumeReviewSheet(selectedResume: .constant(selectedResume))
                }
            }
            .sheet(isPresented: Binding(
                get: { appState.resumeReviseViewModel?.showResumeRevisionSheet ?? false },
                set: { appState.resumeReviseViewModel?.showResumeRevisionSheet = $0 }
            )) {
                if let selectedResume = jobAppStore.selectedApp?.selectedRes,
                   let viewModel = appState.resumeReviseViewModel {
                    RevisionReviewView(
                        viewModel: viewModel,
                        resume: .constant(selectedResume)
                    )
                    .frame(minWidth: 650)
                }
            }
            .sheet(isPresented: $sheets.showClarifyingQuestions) {
                ClarifyingQuestionsSheet(
                    questions: clarifyingQuestions,
                    isPresented: $sheets.showClarifyingQuestions,
                    onSubmit: { answers in
                        Task { @MainActor in
                            guard let jobApp = jobAppStore.selectedApp,
                                  let resume = jobApp.selectedRes,
                                  let viewModel = appState.resumeReviseViewModel else { return }
                            
                            // Create ClarifyingQuestionsViewModel for processing answers
                            let clarifyingViewModel = ClarifyingQuestionsViewModel(
                                llmService: LLMService.shared,
                                appState: appState
                            )
                            
                            // Set the conversation context from the original workflow
                            // This would need to be stored when questions are generated
                            
                            do {
                                try await clarifyingViewModel.processAnswersAndHandoffConversation(
                                    answers: answers,
                                    resume: resume,
                                    resumeReviseViewModel: viewModel
                                )
                            } catch {
                                Logger.error("Error continuing after clarifying questions: \(error)")
                            }
                        }
                    }
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
            }
            .sheet(isPresented: $refPopup) {
                ResRefView()
                    .padding()
            }
    }
}

// MARK: - Helper View Extension

extension View {
    func appSheets(sheets: Binding<AppSheets>, clarifyingQuestions: Binding<[ClarifyingQuestion]>, refPopup: Binding<Bool>) -> some View {
        self.modifier(AppSheetsModifier(sheets: sheets, clarifyingQuestions: clarifyingQuestions, refPopup: refPopup))
    }
}