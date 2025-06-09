//
//  AppWindowView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//  Renamed from TabWrapperView to better reflect responsibility
//

import SwiftUI
import AppKit

struct AppWindowView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(\.appState) private var appState: AppState

    @State private var listingButtons: SaveButtons = .init(edit: false, save: false, cancel: false)
    @Binding var selectedTab: TabList
    @State private var refPopup: Bool = false
    @State private var hasVisitedResumeTab: Bool = false
    @Binding var tabRefresh: Bool
    @Binding var showSlidingList: Bool
    
    // Centralized sheet state management for all app windows/modals
    @State private var sheets = AppSheets()
    @State private var clarifyingQuestions: [ClarifyingQuestion] = []
    
    // Revision workflow - managed by ResumeReviseViewModel
    @State private var resumeReviseViewModel: ResumeReviseViewModel?
    

    var body: some View {
        @Bindable var jobAppStore = jobAppStore
        if let jobApp = jobAppStore.selectedApp {
            @Bindable var jobApp = jobApp
            mainContent
        }
    }
    
    private var mainContent: some View {
        VStack {
            tabView
        }
        .id($tabRefresh.wrappedValue)
        .toolbar {
            buildUnifiedToolbar(
                selectedTab: $selectedTab,
                listingButtons: $listingButtons,
                refresh: $tabRefresh,
                sheets: $sheets,
                clarifyingQuestions: $clarifyingQuestions,
                resumeReviseViewModel: resumeReviseViewModel,
                showNewAppSheet: $sheets.showNewJobApp,
                showSlidingList: $showSlidingList
            )
        }
        .modifier(AppWindowViewModifiers(
            jobAppStore: jobAppStore,
            sheets: $sheets,
            refPopup: $refPopup,
            resumeReviseViewModel: resumeReviseViewModel,
            coverLetterStore: coverLetterStore,
            appState: appState,
            selectedTab: $selectedTab,
            hasVisitedResumeTab: $hasVisitedResumeTab,
            updateMyLetter: updateMyLetter
        ))
    }
    
    private var tabView: some View {
        TabView(selection: $selectedTab) {
            JobAppDetailView(tab: $selectedTab, buttons: $listingButtons)
                .tabItem {
                    Label(TabList.listing.rawValue, systemImage: "newspaper")
                }
                .tag(TabList.listing)

            ResumeSplitView(
                isWide: .constant(true),
                tab: $selectedTab,
                showResumeInspector: $sheets.showResumeInspector,
                refresh: $tabRefresh
            )
                .tabItem {
                    Label(TabList.resume.rawValue, systemImage: "person.crop.rectangle.stack")
                }
                .tag(TabList.resume)

            CoverLetterView(showCoverLetterInspector: $sheets.showCoverLetterInspector)
                .tabItem {
                    Label(TabList.coverLetter.rawValue, systemImage: "person.2.crop.square.stack")
                }
                .tag(TabList.coverLetter)
                .disabled(!jobAppStore.selectedApp!.hasAnyRes)
                
            ResumeExportView()
                .tabItem {
                    Label(TabList.submitApp.rawValue, systemImage: "paperplane")
                }
                .tag(TabList.submitApp)
                .disabled(jobAppStore.selectedApp?.selectedRes == nil)
        }
        .padding(.all)
    }
    

    // MARK: - Toolbar Action Methods
    
    @MainActor
    private func startCustomizeWorkflow(modelId: String) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            return
        }
        
        do {
            guard let viewModel = resumeReviseViewModel else {
                Logger.error("ResumeReviseViewModel not available")
                return
            }
            
            try await viewModel.startFreshRevisionWorkflow(
                resume: resume,
                modelId: modelId
            )
            
        } catch {
            Logger.error("Error in customize workflow: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func startClarifyingQuestionsWorkflow(modelId: String) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            return
        }
        
        do {
            let clarifyingViewModel = ClarifyingQuestionsViewModel(
                llmService: LLMService.shared,
                appState: appState
            )
            
            try await clarifyingViewModel.startClarifyingQuestionsWorkflow(
                resume: resume,
                jobApp: jobApp,
                modelId: modelId
            )
            
            if !clarifyingViewModel.questions.isEmpty {
                Logger.debug("Showing \(clarifyingViewModel.questions.count) clarifying questions")
                clarifyingQuestions = clarifyingViewModel.questions
                sheets.showClarifyingQuestions = true
            } else {
                Logger.debug("AI opted to proceed without clarifying questions")
            }

        } catch {
            Logger.error("Error starting clarifying questions workflow: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func generateCoverLetter(modelId: String) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            return
        }
        
        do {
            try await CoverLetterService.shared.generateNewCoverLetter(
                jobApp: jobApp,
                resume: resume,
                modelId: modelId,
                coverLetterStore: coverLetterStore
            )
            
        } catch {
            Logger.error("Error generating cover letter: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func startBestLetterSelection(modelId: String) async {
        guard let jobApp = jobAppStore.selectedApp else {
            return
        }
        
        do {
            let service = BestCoverLetterService(llmService: LLMService.shared)
            let result = try await service.selectBestCoverLetter(
                jobApp: jobApp, 
                modelId: modelId
            )
            
            Logger.debug("✅ Best cover letter selection completed: \(result.bestLetterUuid)")
            
            // Update the selected cover letter
            if let uuid = UUID(uuidString: result.bestLetterUuid),
               let selectedLetter = jobApp.coverLetters.first(where: { $0.id == uuid }) {
                jobApp.selectedCover = selectedLetter
                Logger.debug("📝 Updated selected cover letter to: \(selectedLetter.sequencedName)")
            }
            
        } catch {
            Logger.error("Error in best letter selection: \(error.localizedDescription)")
        }
    }

    func updateMyLetter() {
        if let selectedApp = jobAppStore.selectedApp {
            // Determine or create the cover letter
            let letter: CoverLetter
            if let lastLetter = selectedApp.coverLetters.last {
                letter = lastLetter
            } else {
                letter = coverLetterStore.create(jobApp: selectedApp)
            }
            coverLetterStore.cL = letter
            // Note: Individual views now manage their own editing state
        } else {
            coverLetterStore.cL = nil
        }
    }
}

struct SaveButtons {
    var edit: Bool = false
    var save: Bool = false
    var cancel: Bool = false
}

// MARK: - View Modifiers


struct AppWindowViewModifiers: ViewModifier {
    let jobAppStore: JobAppStore
    @Binding var sheets: AppSheets
    @Binding var refPopup: Bool
    let resumeReviseViewModel: ResumeReviseViewModel?
    let coverLetterStore: CoverLetterStore
    let appState: AppState
    @Binding var selectedTab: TabList
    @Binding var hasVisitedResumeTab: Bool
    let updateMyLetter: () -> Void
    
    func body(content: Content) -> some View {
        let step1: some View = content
            .onChange(of: jobAppStore.selectedApp) { _, _ in
                updateMyLetter()
            }
            .onChange(of: jobAppStore.selectedApp?.hasAnyRes ?? false) { _, _ in
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .resume {
                    if !hasVisitedResumeTab {
                        sheets.showResumeInspector = false
                        hasVisitedResumeTab = true
                    }
                }
            }
            .onAppear {
                updateMyLetter()
                hasVisitedResumeTab = false
            }
        
        let step2: some View = step1
            .sheet(isPresented: $refPopup) {
                ResRefView()
                    .padding()
            }
            .sheet(isPresented: $sheets.showResumeReview) {
                if let selectedResume = jobAppStore.selectedApp?.selectedRes {
                    ResumeReviewSheet(selectedResume: .constant(selectedResume))
                }
            }
            .sheet(isPresented: Binding(
                get: { resumeReviseViewModel?.showResumeRevisionSheet ?? false },
                set: { resumeReviseViewModel?.showResumeRevisionSheet = $0 }
            )) {
                if let selectedResume = jobAppStore.selectedApp?.selectedRes,
                   let viewModel = resumeReviseViewModel {
                    RevisionReviewView(
                        viewModel: viewModel,
                        resume: .constant(selectedResume)
                    )
                    .frame(minWidth: 650)
                }
            }
        
        let step3: some View = step2
            .sheet(isPresented: $sheets.showMultiModelChooseBest) {
                if jobAppStore.selectedApp != nil,
                   let currentCoverLetter = coverLetterStore.cL {
                    MultiModelChooseBestCoverLetterSheet(coverLetter: .constant(currentCoverLetter))
                }
            }
            .sheet(isPresented: $sheets.showNewJobApp) {
                NewAppSheetView(
                    scrapingDogApiKey: UserDefaults.standard.string(forKey: "scrapingDogApiKey") ?? "none",
                    isPresented: $sheets.showNewJobApp
                )
                .environment(jobAppStore)
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
            .sheet( isPresented: $sheets.showBatchCoverLetter) {
                BatchCoverLetterView()
                    .environment(appState)
                    .environment(jobAppStore)
                    .environment(coverLetterStore)
            }
        
        return step3
    }
}



