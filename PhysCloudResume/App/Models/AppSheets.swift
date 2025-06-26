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
    
    // State to control RevisionReviewView sheet via notifications
    @State private var showRevisionReviewSheet = false
    
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
            .sheet(isPresented: $showRevisionReviewSheet) {
                if let selectedResume = jobAppStore.selectedApp?.selectedRes,
                   let viewModel = appState.resumeReviseViewModel {
                    let _ = Logger.debug("🔍 [AppSheets] Creating RevisionReviewView with resume: \(selectedResume.id.uuidString)")
                    let _ = Logger.debug("🔍 [AppSheets] ViewModel has \(viewModel.resumeRevisions.count) revisions")
                    RevisionReviewView(
                        viewModel: viewModel,
                        resume: .constant(selectedResume)
                    )
                    .frame(minWidth: 650)
                } else {
                    let _ = Logger.debug("🔍 [AppSheets] Failed to get selectedResume or viewModel")
                    let _ = Logger.debug("🔍 [AppSheets] jobAppStore.selectedApp: \(jobAppStore.selectedApp?.id.uuidString ?? "nil")")
                    let _ = Logger.debug("🔍 [AppSheets] jobAppStore.selectedApp?.selectedRes: \(jobAppStore.selectedApp?.selectedRes?.id.uuidString ?? "nil")")
                    let _ = Logger.debug("🔍 [AppSheets] appState.resumeReviseViewModel: \(appState.resumeReviseViewModel != nil ? "exists" : "nil")")
                    if let vm = appState.resumeReviseViewModel {
                        let _ = Logger.debug("🔍 [AppSheets] ViewModel revisions count: \(vm.resumeRevisions.count)")
                    }
                    Text("Error: Missing resume or viewModel")
                        .frame(width: 400, height: 300)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showResumeRevisionSheet)) { _ in
                Logger.debug("🔍 [AppSheets] Received showResumeRevisionSheet notification")
                showRevisionReviewSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .hideResumeRevisionSheet)) { _ in
                Logger.debug("🔍 [AppSheets] Received hideResumeRevisionSheet notification")
                showRevisionReviewSheet = false
            }
            .onChange(of: showRevisionReviewSheet) { _, newValue in
                // Sync sheet state back to ViewModel when manually closed
                if !newValue {
                    Logger.debug("🔍 [AppSheets] Sheet dismissed, syncing back to ViewModel")
                    appState.resumeReviseViewModel?.showResumeRevisionSheet = false
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