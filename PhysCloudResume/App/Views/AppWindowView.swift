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
    
    // Centralized sheet state management for all app windows/modals
    @State private var sheets = AppSheets()
    @State private var clarifyingQuestions: [ClarifyingQuestion] = []
    
    // Revision workflow - managed by ResumeReviseViewModel
    @State private var resumeReviseViewModel: ResumeReviseViewModel?
    
    // State for AppKit toolbar coordination
    @State private var showCustomizeModelSheet = false
    @State private var showClarifyingQuestionsModelSheet = false
    @State private var showCoverLetterModelSheet = false
    @State private var showBestLetterModelSheet = false

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
        .modifier(AppWindowViewModifiers(
            jobAppStore: jobAppStore,
            sheets: $sheets,
            refPopup: $refPopup,
            resumeReviseViewModel: resumeReviseViewModel,
            coverLetterStore: coverLetterStore,
            appState: appState,
            selectedTab: $selectedTab,
            hasVisitedResumeTab: $hasVisitedResumeTab,
            showCustomizeModelSheet: $showCustomizeModelSheet,
            showClarifyingQuestionsModelSheet: $showClarifyingQuestionsModelSheet,
            showCoverLetterModelSheet: $showCoverLetterModelSheet,
            showBestLetterModelSheet: $showBestLetterModelSheet,
            startCustomizeWorkflow: startCustomizeWorkflow,
            startClarifyingQuestionsWorkflow: startClarifyingQuestionsWorkflow,
            generateCoverLetter: generateCoverLetter,
            startBestLetterSelection: startBestLetterSelection,
            updateMyLetter: updateMyLetter,
            setupToolbarNotificationHandlers: setupToolbarNotificationHandlers
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
    
    private func setupToolbarNotificationHandlers() {
        // Legacy SwiftUI toolbar notifications
        NotificationCenter.default.addObserver(
            forName: .showCustomizeModelSheet,
            object: nil,
            queue: .main
        ) { _ in
            showCustomizeModelSheet = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .showClarifyingQuestionsModelSheet,
            object: nil,
            queue: .main
        ) { _ in
            showClarifyingQuestionsModelSheet = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .showCoverLetterModelSheet,
            object: nil,
            queue: .main
        ) { _ in
            showCoverLetterModelSheet = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .showBestLetterModelSheet,
            object: nil,
            queue: .main
        ) { _ in
            showBestLetterModelSheet = true
        }
        
        // AppKit toolbar notifications
        NotificationCenter.default.addObserver(
            forName: .toolbarNewJobApp,
            object: nil,
            queue: .main
        ) { _ in
            sheets.showNewJobApp = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .toolbarBestJob,
            object: nil,
            queue: .main
        ) { _ in
            // Trigger best job functionality
            // This would need to be implemented properly
        }
        
        NotificationCenter.default.addObserver(
            forName: .toolbarCustomize,
            object: nil,
            queue: .main
        ) { _ in
            selectedTab = .resume
            showCustomizeModelSheet = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .toolbarClarifyCustomize,
            object: nil,
            queue: .main
        ) { _ in
            selectedTab = .resume
            showClarifyingQuestionsModelSheet = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .toolbarOptimize,
            object: nil,
            queue: .main
        ) { _ in
            sheets.showResumeReview = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .toolbarCoverLetter,
            object: nil,
            queue: .main
        ) { _ in
            showCoverLetterModelSheet = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .toolbarBatchLetter,
            object: nil,
            queue: .main
        ) { _ in
            sheets.showBatchCoverLetter = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .toolbarBestLetter,
            object: nil,
            queue: .main
        ) { _ in
            showBestLetterModelSheet = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .toolbarCommittee,
            object: nil,
            queue: .main
        ) { _ in
            sheets.showMultiModelChooseBest = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .toolbarAnalyze,
            object: nil,
            queue: .main
        ) { _ in
            sheets.showApplicationReview = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .toolbarInspector,
            object: nil,
            queue: .main
        ) { _ in
            switch selectedTab {
            case .resume:
                sheets.showResumeInspector.toggle()
            case .coverLetter:
                sheets.showCoverLetterInspector.toggle()
            default:
                break
            }
        }
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
    @Binding var showCustomizeModelSheet: Bool
    @Binding var showClarifyingQuestionsModelSheet: Bool
    @Binding var showCoverLetterModelSheet: Bool
    @Binding var showBestLetterModelSheet: Bool
    let startCustomizeWorkflow: (String) async -> Void
    let startClarifyingQuestionsWorkflow: (String) async -> Void
    let generateCoverLetter: (String) async -> Void
    let startBestLetterSelection: (String) async -> Void
    let updateMyLetter: () -> Void
    let setupToolbarNotificationHandlers: () -> Void
    
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
                setupToolbarNotificationHandlers()
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
            .appKitToolbarModelSheets(
                showCustomizeModelSheet: $showCustomizeModelSheet,
                showClarifyingQuestionsModelSheet: $showClarifyingQuestionsModelSheet,
                showCoverLetterModelSheet: $showCoverLetterModelSheet,
                showBestLetterModelSheet: $showBestLetterModelSheet,
                startCustomizeWorkflow: startCustomizeWorkflow,
                startClarifyingQuestionsWorkflow: startClarifyingQuestionsWorkflow,
                generateCoverLetter: generateCoverLetter,
                startBestLetterSelection: startBestLetterSelection
            )
        
        return step3
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let showCustomizeModelSheet = Notification.Name("showCustomizeModelSheet")
    static let showClarifyingQuestionsModelSheet = Notification.Name("showClarifyingQuestionsModelSheet")
    static let showCoverLetterModelSheet = Notification.Name("showCoverLetterModelSheet")
    static let showBestLetterModelSheet = Notification.Name("showBestLetterModelSheet")
}

extension View {
    func appKitToolbarModelSheets(
        showCustomizeModelSheet: Binding<Bool>,
        showClarifyingQuestionsModelSheet: Binding<Bool>,
        showCoverLetterModelSheet: Binding<Bool>,
        showBestLetterModelSheet: Binding<Bool>,
        startCustomizeWorkflow: @escaping (String) async -> Void,
        startClarifyingQuestionsWorkflow: @escaping (String) async -> Void,
        generateCoverLetter: @escaping (String) async -> Void,
        startBestLetterSelection: @escaping (String) async -> Void
    ) -> some View {
        self
            .sheet(isPresented: showCustomizeModelSheet) {
                ModelSelectionSheet(
                    title: "Choose Model for Resume Customization",
                    requiredCapability: .structuredOutput,
                    operationKey: "resume_customize",
                    isPresented: showCustomizeModelSheet,
                    onModelSelected: { modelId in
                        Task {
                            await startCustomizeWorkflow(modelId)
                        }
                    }
                )
            }
            .sheet(isPresented: showClarifyingQuestionsModelSheet) {
                ModelSelectionSheet(
                    title: "Choose Model for Clarifying Questions",
                    requiredCapability: .structuredOutput,
                    operationKey: "clarifying_questions",
                    isPresented: showClarifyingQuestionsModelSheet,
                    onModelSelected: { modelId in
                        Task {
                            await startClarifyingQuestionsWorkflow(modelId)
                        }
                    }
                )
            }
            .sheet(isPresented: showCoverLetterModelSheet) {
                ModelSelectionSheet(
                    title: "Choose Model for Cover Letter Generation",
                    requiredCapability: nil,
                    operationKey: "cover_letter",
                    isPresented: showCoverLetterModelSheet,
                    onModelSelected: { modelId in
                        Task {
                            await generateCoverLetter(modelId)
                        }
                    }
                )
            }
            .sheet(isPresented: showBestLetterModelSheet) {
                ModelSelectionSheet(
                    title: "Choose Model for Best Cover Letter Selection",
                    requiredCapability: .structuredOutput,
                    operationKey: "best_letter",
                    isPresented: showBestLetterModelSheet,
                    onModelSelected: { modelId in
                        Task {
                            await startBestLetterSelection(modelId)
                        }
                    }
                )
            }
    }
}


