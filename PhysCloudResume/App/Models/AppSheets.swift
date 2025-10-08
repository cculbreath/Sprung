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
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(AppState.self) private var appState
    
    private var revisionSheetBinding: Binding<Bool> {
        Binding(
            get: { appState.resumeReviseViewModel?.showResumeRevisionSheet ?? false },
            set: { newValue in
                guard let viewModel = appState.resumeReviseViewModel else { return }
                viewModel.showResumeRevisionSheet = newValue
            }
        )
    }
    
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
            .sheet(isPresented: revisionSheetBinding) {
                if let selectedResume = jobAppStore.selectedApp?.selectedRes,
                   let viewModel = appState.resumeReviseViewModel {
                    RevisionReviewView(
                        viewModel: viewModel,
                        resume: .constant(selectedResume)
                    )
                    .frame(minWidth: 650)
                    .onAppear {
                        Logger.debug(
                            "🔍 [AppSheets] Creating RevisionReviewView with resume: \(selectedResume.id.uuidString)",
                            category: .ui
                        )
                        Logger.debug(
                            "🔍 [AppSheets] ViewModel has \(viewModel.resumeRevisions.count) revisions",
                            category: .ui
                        )
                    }
                } else {
                    Text("Error: Missing resume or viewModel")
                        .frame(width: 400, height: 300)
                        .onAppear {
                            Logger.debug("🔍 [AppSheets] Failed to get selectedResume or viewModel", category: .ui)
                            Logger.debug("🔍 [AppSheets] jobAppStore.selectedApp: \(jobAppStore.selectedApp?.id.uuidString ?? "nil")", category: .ui)
                            Logger.debug("🔍 [AppSheets] jobAppStore.selectedApp?.selectedRes: \(jobAppStore.selectedApp?.selectedRes?.id.uuidString ?? "nil")", category: .ui)
                            Logger.debug("🔍 [AppSheets] appState.resumeReviseViewModel: \(appState.resumeReviseViewModel != nil ? "exists" : "nil")", category: .ui)
                            if let vm = appState.resumeReviseViewModel {
                                Logger.debug(
                                    "🔍 [AppSheets] ViewModel revisions count: \(vm.resumeRevisions.count)",
                                    category: .ui
                                )
                            }
                        }
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
    }
}

// MARK: - Helper View Extension

extension View {
    func appSheets(sheets: Binding<AppSheets>, clarifyingQuestions: Binding<[ClarifyingQuestion]>, refPopup: Binding<Bool>) -> some View {
        self.modifier(AppSheetsModifier(sheets: sheets, clarifyingQuestions: clarifyingQuestions, refPopup: refPopup))
    }
}
