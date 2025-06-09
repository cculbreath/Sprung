// PhysCloudResume/App/Views/UnifiedToolbar.swift
import SwiftUI
import AppKit


/// Unified toolbar with all buttons visible, using disabled state instead of hiding
@ToolbarContentBuilder
func buildUnifiedToolbar(
    selectedTab: Binding<TabList>,
    listingButtons: Binding<SaveButtons>,
    refresh: Binding<Bool>,
    sheets: Binding<AppSheets>,
    clarifyingQuestions: Binding<[ClarifyingQuestion]>,
    resumeReviseViewModel: ResumeReviseViewModel?,
    showNewAppSheet: Binding<Bool>,
    showSlidingList: Binding<Bool>
) -> some CustomizableToolbarContent {
    UnifiedToolbar(
        selectedTab: selectedTab,
        listingButtons: listingButtons,
        refresh: refresh,
        sheets: sheets,
        clarifyingQuestions: clarifyingQuestions,
        resumeReviseViewModel: resumeReviseViewModel,
        showNewAppSheet: showNewAppSheet,
        showSlidingList: showSlidingList
    )
}

struct UnifiedToolbar: CustomizableToolbarContent {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(AppState.self) private var appState: AppState
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore

    @Binding var selectedTab: TabList
    @Binding var listingButtons: SaveButtons
    @Binding var refresh: Bool
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]
    var resumeReviseViewModel: ResumeReviseViewModel?
    @Binding var showNewAppSheet: Bool
    @Binding var showSlidingList: Bool

    @State private var isGeneratingResume = false
    @State private var isGeneratingCoverLetter = false
    @State private var isGeneratingQuestions = false

    @State private var showClarifyingQuestionsModelSheet = false
    @State private var selectedClarifyingQuestionsModel = ""
    @State private var clarifyingQuestionsViewModel: ClarifyingQuestionsViewModel?
    
    @State private var showCustomizeModelSheet = false
    @State private var selectedCustomizeModel = ""
    
    
    @State private var showCoverLetterModelSheet = false
    @State private var selectedCoverLetterModel = ""
    
    @State private var showBestLetterModelSheet = false
    @State private var selectedBestLetterModel = ""
    @State private var isProcessingBestLetter = false
    @State private var showBestLetterAlert = false
    @State private var bestLetterResult: BestCoverLetterResponse?
    
    @State private var showBestJobModelSheet = false
    @State private var selectedBestJobModel = ""
    @State private var isProcessingBestJob = false
    @State private var showBestJobAlert = false
    @State private var bestJobResult: String?
    

    private var selectedResumeBinding: Binding<Resume?> {
        Binding<Resume?>(
            get: { jobAppStore.selectedApp?.selectedRes },
            set: { newValue in
                if jobAppStore.selectedApp != nil {
                    jobAppStore.selectedApp!.selectedRes = newValue
                }
            }
        )
    }

    /// Processes clarifying question answers and generates resume revisions
    /// This continues the multi-turn conversation and hands off to ResumeReviseViewModel
    @MainActor
    private func processClarifyingQuestionsAnswers(answers: [QuestionAnswer]) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            return
        }
        
        do {
            // Use the clarifying questions ViewModel to process answers
            guard let clarifyingViewModel = clarifyingQuestionsViewModel else {
                Logger.error("ClarifyingQuestionsViewModel not available for processing answers")
                return
            }
            
            guard let resumeViewModel = resumeReviseViewModel else {
                Logger.error("ResumeReviseViewModel not available for handoff")
                return
            }
            
            // Process answers and hand off conversation
            try await clarifyingViewModel.processAnswersAndHandoffConversation(
                answers: answers,
                resume: resume,
                resumeReviseViewModel: resumeViewModel
            )
            
            Logger.debug("✅ Clarifying questions processed and handed off to ResumeReviseViewModel")
            
        } catch {
            Logger.error("Error processing clarifying questions answers: \\(error.localizedDescription)")
        }
        
        // Clear busy state when processing completes (success or error)
        isGeneratingQuestions = false
    }

    /// Starts the resume customization workflow with the selected model
    @MainActor 
    private func startCustomizeWorkflow(modelId: String) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            isGeneratingResume = false
            return
        }
        
        do {
            // Use the ResumeReviseViewModel passed from TabWrapperView
            guard let viewModel = resumeReviseViewModel else {
                Logger.error("ResumeReviseViewModel not available")
                isGeneratingResume = false
                return
            }
            
            // Start fresh revision workflow - ResumeReviseViewModel manages everything
            try await viewModel.startFreshRevisionWorkflow(
                resume: resume,
                modelId: modelId
            )
            
            isGeneratingResume = false
            
        } catch {
            Logger.error("Error in customize workflow: \(error.localizedDescription)")
            isGeneratingResume = false
        }
    }

    /// Starts the best cover letter selection with the selected model
    @MainActor
    private func startBestLetterSelection(modelId: String) async {
        guard let jobApp = jobAppStore.selectedApp else {
            isProcessingBestLetter = false
            return
        }
        
        do {
            let service = BestCoverLetterService(llmService: LLMService.shared)
            let result = try await service.selectBestCoverLetter(
                jobApp: jobApp, 
                modelId: modelId
            )
            
            isProcessingBestLetter = false
            bestLetterResult = result
            showBestLetterAlert = true
            
            Logger.debug("✅ Best cover letter selection completed: \(result.bestLetterUuid)")
            
        } catch {
            isProcessingBestLetter = false
            Logger.error("Error in best letter selection: \(error.localizedDescription)")
            
            // Show error in alert
            bestLetterResult = BestCoverLetterResponse(
                strengthAndVoiceAnalysis: "Error occurred during selection",
                bestLetterUuid: "",
                verdict: "Selection failed: \(error.localizedDescription)"
            )
            showBestLetterAlert = true
        }
    }

    /// Starts the clarifying questions workflow with the selected model
    @MainActor
    private func startClarifyingQuestionsWorkflow(modelId: String) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            isGeneratingQuestions = false
            return
        }
        
        do {
            // Create and store the ClarifyingQuestionsViewModel
            let clarifyingViewModel = ClarifyingQuestionsViewModel(
                llmService: LLMService.shared,
                appState: appState
            )
            clarifyingQuestionsViewModel = clarifyingViewModel
            
            // Start the clarifying questions workflow
            try await clarifyingViewModel.startClarifyingQuestionsWorkflow(
                resume: resume,
                jobApp: jobApp,
                modelId: modelId
            )
            
            // Check if questions were generated
            if !clarifyingViewModel.questions.isEmpty {
                // Questions were generated - show the sheet
                Logger.debug("Showing \(clarifyingViewModel.questions.count) clarifying questions")
                clarifyingQuestions = clarifyingViewModel.questions
                sheets.showClarifyingQuestions = true
            } else {
                // No questions needed - AI opted to proceed directly to revisions
                Logger.debug("AI opted to proceed without clarifying questions")
            }
            
            isGeneratingQuestions = false

        } catch {
            Logger.error("Error starting clarifying questions workflow: \(error.localizedDescription)")
            isGeneratingQuestions = false
        }
    }

    /// Generates a cover letter with the selected model
    @MainActor
    private func generateCoverLetter(modelId: String) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            isGeneratingCoverLetter = false
            return
        }
        
        do {
            // Delegate to CoverLetterService for all business logic
            try await CoverLetterService.shared.generateNewCoverLetter(
                jobApp: jobApp,
                resume: resume,
                modelId: modelId,
                coverLetterStore: coverLetterStore
            )
            
            isGeneratingCoverLetter = false
            
        } catch {
            Logger.error("Error generating cover letter: \(error.localizedDescription)")
            isGeneratingCoverLetter = false
            // TODO: Show error alert to user
        }
    }

    var body: some CustomizableToolbarContent {
        Group {
            navigationButtonsGroup
            mainButtonsGroup
            inspectorButtonGroup
        }
    }
    
    private var navigationButtonsGroup: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: "newJobApp", placement: .primaryAction, showsByDefault: true) {
                newJobAppButton()
            }
            
            ToolbarItem(id: "bestJob", placement: .primaryAction, showsByDefault: true) {
                bestJobButton()
            }
            
            ToolbarItem(id: "showSources", placement: .primaryAction, showsByDefault: true) {
                showSourcesButton()
            }
        }
    }
    
    private var mainButtonsGroup: some CustomizableToolbarContent {
        Group {
            // Resume Operations
            ToolbarItem(id: "customize", placement: .primaryAction, showsByDefault: true) {
                resumeButton("Customize", "wand.and.sparkles", action: {
                    selectedTab = .resume
                    showCustomizeModelSheet = true
                }, disabled: selectedResumeBinding.wrappedValue?.rootNode == nil,
                             help: "Create Resume Revisions")
            }
            
            ToolbarItem(id: "clarifyCustomize", placement: .primaryAction, showsByDefault: true) {
                clarifyAndCustomizeButton()
            }
            
            ToolbarItem(id: "optimize", placement: .primaryAction, showsByDefault: true) {
                resumeButton("Optimize", "character.magnify", action: {
                    sheets.showResumeReview = true
                }, disabled: selectedResumeBinding.wrappedValue == nil,
                             help: "AI Resume Review")
            }
            
            // Cover Letter Operations
            ToolbarItem(id: "coverLetter", placement: .primaryAction, showsByDefault: true) {
                coverLetterGenerateButton()
            }
            
            ToolbarItem(id: "batchLetter", placement: .primaryAction, showsByDefault: true) {
                coverLetterButton("Batch Letter", "square.stack.3d.up.fill", action: {
                    sheets.showBatchCoverLetter = true
                }, disabled: jobAppStore.selectedApp?.selectedRes == nil,
                              help: "Batch Cover Letter Operations")
            }
            
            ToolbarItem(id: "bestLetter", placement: .primaryAction, showsByDefault: true) {
                bestLetterButton()
            }
            
            ToolbarItem(id: "committee", placement: .primaryAction, showsByDefault: true) {
                Button(action: {
                    sheets.showMultiModelChooseBest = true
                }) {
                    Label {
                        Text("Committee")
                    } icon: {
                        Image("custom.medal.square.stack")
                    }
                }
                .help("Multi-model Choose Best Cover Letter")
                .disabled((jobAppStore.selectedApp?.coverLetters.filter { $0.generated }.count ?? 0) < 2)
            }
            
            // Conditional TTS and Analyze buttons
            if UserDefaults.standard.bool(forKey: "ttsEnabled") {
                ToolbarItem(id: "tts", placement: .primaryAction, showsByDefault: false) {
                    TTSButton()
                        .disabled(coverLetterStore.cL?.generated != true)
                }
            }
            
            ToolbarItem(id: "analyze", placement: .primaryAction, showsByDefault: true) {
                sidebarButton("Analyze", "mail.and.text.magnifyingglass", action: {
                    sheets.showApplicationReview = true
                }, disabled: jobAppStore.selectedApp?.selectedRes == nil ||
                              jobAppStore.selectedApp?.selectedCover == nil ||
                              jobAppStore.selectedApp?.selectedCover?.generated != true,
                              help: "Review Application")
            }
        }
    }
    
    private var inspectorButtonGroup: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: "inspector", placement: .primaryAction, showsByDefault: true) {
                sidebarButton("Inspector", "sidebar.right", action: {
                    switch selectedTab {
                    case .resume:
                        sheets.showResumeInspector.toggle()
                    case .coverLetter:
                        sheets.showCoverLetterInspector.toggle()
                    default:
                        break // No inspector for other tabs
                    }
                }, disabled: selectedTab != .resume && selectedTab != .coverLetter,
                              help: selectedTab == .resume ? "Show Resume Inspector" : 
                                    selectedTab == .coverLetter ? "Show Cover Letter Inspector" : "Inspector")
            }
            
            // Hidden by default but customizable toolbar items
            ToolbarItem(id: "settings", placement: .primaryAction, showsByDefault: false) {
                settingsButton()
            }
            
            ToolbarItem(id: "applicantProfile", placement: .primaryAction, showsByDefault: false) {
                applicantProfileButton()
            }
            
            ToolbarItem(id: "templateEditor", placement: .primaryAction, showsByDefault: false) {
                templateEditorButton()
            }
        }
    }

    @ViewBuilder
    private func clarifyAndCustomizeButton() -> some View {
        Button(action: {
            selectedTab = .resume
            clarifyingQuestions = []
            showClarifyingQuestionsModelSheet = true
        }) {
            if isGeneratingQuestions {
                Label {
                    Text("Clarify & Customize")
                } icon: {
                    Image("custom.wand.and.rays.inverse.badge.questionmark")
                        .symbolEffect(.variableColor.iterative.hideInactiveLayers.nonReversing)
                }
            } else {
                Label {
                    Text("Clarify & Customize")
                } icon: {
                    Image("custom.wand.and.sparkles.badge.questionmark")
                }
            }
        }
        .help("Create Resume Revisions with Clarifying Questions")
        .disabled(selectedResumeBinding.wrappedValue?.rootNode == nil)
        .sheet(isPresented: $showClarifyingQuestionsModelSheet) {
            ModelSelectionSheet(
                title: "Choose Model for Clarifying Questions",
                requiredCapability: .structuredOutput,
                operationKey: "clarifying_questions",
                isPresented: $showClarifyingQuestionsModelSheet,
                onModelSelected: { modelId in
                    selectedClarifyingQuestionsModel = modelId
                    isGeneratingQuestions = true
                    Task {
                        await startClarifyingQuestionsWorkflow(modelId: modelId)
                    }
                }
            )
        }
        .sheet(isPresented: $showCustomizeModelSheet) {
            ModelSelectionSheet(
                title: "Choose Model for Resume Customization",
                requiredCapability: .structuredOutput,
                operationKey: "resume_customize",
                isPresented: $showCustomizeModelSheet,
                onModelSelected: { modelId in
                    selectedCustomizeModel = modelId
                    isGeneratingResume = true
                    Task {
                        await startCustomizeWorkflow(modelId: modelId)
                    }
                }
            )
        }
        .sheet(isPresented: $sheets.showClarifyingQuestions) {
            ClarifyingQuestionsSheet(
                questions: clarifyingQuestions,
                isPresented: $sheets.showClarifyingQuestions,
                onSubmit: { answers in
                    sheets.showClarifyingQuestions = false
                    isGeneratingQuestions = true
                    Task {
                        await processClarifyingQuestionsAnswers(answers: answers)
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private func coverLetterGenerateButton() -> some View {
        Button(action: {
            showCoverLetterModelSheet = true
        }) {
            Label {
                Text("Cover Letter")
            } icon: {
                if isGeneratingCoverLetter {
                    Image("custom.append.page.badge.plus")
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
                } else {
                    Image("custom.append.page.badge.plus")
                }
            }
        }
        .help("Generate Cover Letter")
        .disabled(jobAppStore.selectedApp?.selectedRes == nil)
        .sheet(isPresented: $showCoverLetterModelSheet) {
            ModelSelectionSheet(
                title: "Choose Model for Cover Letter Generation",
                requiredCapability: nil,
                operationKey: "cover_letter",
                isPresented: $showCoverLetterModelSheet,
                onModelSelected: { modelId in
                    selectedCoverLetterModel = modelId
                    showCoverLetterModelSheet = false
                    isGeneratingCoverLetter = true
                    
                    Task {
                        await generateCoverLetter(modelId: modelId)
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private func bestLetterButton() -> some View {
        Button(action: {
            showBestLetterModelSheet = true
        }) {
            if isProcessingBestLetter {
                Label("Best Letter", systemImage: "gearshape")
                    .symbolEffect(.rotate, options: .repeating)
            } else {
                Label("Best Letter", systemImage: "medal")
            }
        }
        .help("Choose Best Cover Letter")
        .disabled((jobAppStore.selectedApp?.coverLetters.filter { $0.generated }.count ?? 0) < 2)
        .sheet(isPresented: $showBestLetterModelSheet) {
            ModelSelectionSheet(
                title: "Choose Model for Best Cover Letter Selection",
                requiredCapability: .structuredOutput,
                operationKey: "best_letter",
                isPresented: $showBestLetterModelSheet,
                onModelSelected: { modelId in
                    selectedBestLetterModel = modelId
                    showBestLetterModelSheet = false
                    isProcessingBestLetter = true
                    
                    Task {
                        await startBestLetterSelection(modelId: modelId)
                    }
                }
            )
        }
        .alert("Best Cover Letter Selection", isPresented: $showBestLetterAlert) {
            Button("OK") {
                if let result = bestLetterResult,
                   let uuid = UUID(uuidString: result.bestLetterUuid),
                   let jobApp = jobAppStore.selectedApp,
                   let selectedLetter = jobApp.coverLetters.first(where: { $0.id == uuid }) {
                    jobApp.selectedCover = selectedLetter
                    Logger.debug("📝 Updated selected cover letter to: \(selectedLetter.sequencedName)")
                }
            }
        } message: {
            if let result = bestLetterResult {
                Text("Analysis: \(result.strengthAndVoiceAnalysis)\n\nVerdict: \(result.verdict)")
            }
        }
    }

    // Helper functions for consistent button styling
    @ViewBuilder
    private func resumeButton(_ title: String,
                              _ systemName: String,
                              action: @escaping () -> Void,
                              disabled: Bool = false,
                              help: String) -> some View {
        Button(action: action) {
            if isGeneratingResume && (title == "Customize") {
                Label(title, systemImage: "wand.and.rays")
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
            } else {
                Label(title, systemImage: systemName)
            }
        }
        .help(help)
        .disabled(disabled)
    }

    @ViewBuilder
    private func coverLetterButton(_ title: String,
                                   _ systemName: String,
                                   action: @escaping () -> Void,
                                   disabled: Bool = false,
                                   help: String) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
        }
        .help(help)
        .disabled(disabled)
    }


    @ViewBuilder
    private func sidebarButton(_ title: String,
                               _ systemName: String,
                               action: @escaping () -> Void,
                               disabled: Bool = false,
                               help: String) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
        }
        .help(help)
        .disabled(disabled)
    }

    @ViewBuilder
    private func newJobAppButton() -> some View {
        Button(action: {
            showNewAppSheet = true
        }) {
            Label("New App", systemImage: "note.text.badge.plus")
        }
        .help("Create New Job Application")
    }

    @ViewBuilder
    private func showSourcesButton() -> some View {
        Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.2)) {
                showSlidingList.toggle()
            }
        } label: {
            Label("Show Sources", systemImage: "newspaper")
        }
        .help("Show Sources")
    }

    @ViewBuilder
    private func settingsButton() -> some View {
        Button(action: {
            NotificationCenter.default.post(name: .showSettings, object: nil)
        }) {
            Label("Settings", systemImage: "gear")
        }
        .help("Open Settings")
    }

    @ViewBuilder
    private func applicantProfileButton() -> some View {
        Button(action: {
            NotificationCenter.default.post(name: .showApplicantProfile, object: nil)
        }) {
            Label("Applicant Profile", systemImage: "person.crop.circle")
        }
        .help("Open Applicant Profile")
    }

    @ViewBuilder
    private func templateEditorButton() -> some View {
        Button(action: {
            NotificationCenter.default.post(name: .showTemplateEditor, object: nil)
        }) {
            Label("Template Editor", systemImage: "doc.text")
        }
        .help("Open Template Editor")
    }

    @ViewBuilder
    private func bestJobButton() -> some View {
        Button(action: {
            showBestJobModelSheet = true
        }) {
            if isProcessingBestJob {
                Label("Best Job", systemImage: "wand.and.rays")
                    .symbolEffect(.variableColor.iterative.hideInactiveLayers.nonReversing)
            } else {
                Label("Best Job", systemImage: "medal.star")
            }
        }
        .help("Find the best job match based on your qualifications")
        .disabled(isProcessingBestJob || jobAppStore.selectedApp?.selectedRes == nil)
        .sheet(isPresented: $showBestJobModelSheet) {
            ModelSelectionSheet(
                title: "Choose Model for Job Recommendation",
                requiredCapability: .structuredOutput,
                operationKey: "best_job",
                isPresented: $showBestJobModelSheet,
                onModelSelected: { modelId in
                    selectedBestJobModel = modelId
                    showBestJobModelSheet = false
                    isProcessingBestJob = true
                    
                    Task {
                        await startBestJobRecommendation(modelId: modelId)
                    }
                }
            )
        }
        .alert("Job Recommendation", isPresented: $showBestJobAlert) {
            Button("OK") {
                bestJobResult = nil
            }
        } message: {
            if let result = bestJobResult {
                Text(result)
            }
        }
    }

    /// Starts the best job recommendation with the selected model
    @MainActor
    private func startBestJobRecommendation(modelId: String) async {
        guard let selectedResume = jobAppStore.selectedApp?.selectedRes else {
            isProcessingBestJob = false
            bestJobResult = "Please select a resume first"
            showBestJobAlert = true
            return
        }

        do {
            let service = JobRecommendationService(llmService: LLMService.shared)
            
            let (jobId, reason) = try await service.fetchRecommendation(
                jobApps: jobAppStore.jobApps,
                resume: selectedResume,
                modelId: modelId
            )

            // Find the job with the recommended ID
            if let recommendedJob = jobAppStore.jobApps.first(where: { $0.id == jobId }) {
                // Set as selected job
                jobAppStore.selectedApp = recommendedJob

                // Store the recommended job ID for highlighting
                appState.recommendedJobId = jobId

                // Show recommendation in alert
                bestJobResult = "Recommended: \(recommendedJob.jobPosition) at \(recommendedJob.companyName)\n\nReason: \(reason)"
                showBestJobAlert = true
            } else {
                bestJobResult = "Recommended job not found"
                showBestJobAlert = true
            }

            isProcessingBestJob = false
            
        } catch {
            Logger.error("JobRecommendation Error: \(error)")
            
            // Provide more specific error messages for common issues
            if let llmError = error as? LLMError {
                switch llmError {
                case .unauthorized(let modelId):
                    bestJobResult = "Access denied for model '\(modelId)'.\n\nThis model may require special authorization or billing setup. Try using a different model like GPT-4.1 instead."
                default:
                    bestJobResult = "Error: \(error.localizedDescription)"
                }
            } else {
                bestJobResult = "Error: \(error.localizedDescription)"
            }
            
            showBestJobAlert = true
            isProcessingBestJob = false
        }
    }
}

// TTS Button
struct TTSButton: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false

    var body: some View {
        if ttsEnabled {
            Button(action: {
                // TTS action
            }) {
                Label("Read Aloud", systemImage: "speaker.wave.2")
            }
            .help("Read Cover Letter")
        }
    }
}

// Placeholder for Choose Best Cover Letter Sheet
