// PhysCloudResume/App/Views/ToolbarButtons/ClarifyingQuestionsButton.swift
import SwiftUI

struct ClarifyingQuestionsButton: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(AppState.self) private var appState: AppState
    
    @Binding var selectedTab: TabList
    @Binding var clarifyingQuestions: [ClarifyingQuestion]
    @Binding var sheets: AppSheets
    var resumeReviseViewModel: ResumeReviseViewModel?
    
    @State private var isGeneratingQuestions = false
    @State private var showClarifyingQuestionsModelSheet = false
    @State private var selectedClarifyingQuestionsModel = ""
    @State private var clarifyingQuestionsViewModel: ClarifyingQuestionsViewModel?
    @State private var clarifyingQuestionsConversationId: UUID?
    
    var body: some View {
        Button(action: {
            selectedTab = .resume
            // Don't clear questions here - they might be needed for the sheet
            showClarifyingQuestionsModelSheet = true
        }) {
            if isGeneratingQuestions {
                Label {
                    Text("Clarify & Customize")
                } icon: {
                    Image("custom.wand.and.rays.inverse.badge.questionmark").fontWeight(.bold).foregroundColor(.blue)
                        .symbolEffect(.variableColor.iterative.nonReversing)
                        .font(.system(size: 14, weight: .light))
                }
            } else {
                Label {
                    Text("Clarify & Customize")
                } icon: {
                    Image("custom.wand.and.sparkles.badge.questionmark")
                        .font(.system(size: 14, weight: .light))
                }
            }
        }
        .font(.system(size: 14, weight: .light))
        .buttonStyle( .automatic )
        .help("Create Resume Revisions with Clarifying Questions")
        .disabled(jobAppStore.selectedApp == nil || jobAppStore.selectedApp?.selectedRes?.rootNode == nil)
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
        .onReceive(NotificationCenter.default.publisher(for: .triggerClarifyingQuestionsButton)) { _ in
            // Programmatically trigger the button action (from menu commands)
            selectedTab = .resume
            // Don't clear questions here either
            showClarifyingQuestionsModelSheet = true
        }
    }
    
    @MainActor
    private func startClarifyingQuestionsWorkflow(modelId: String) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            isGeneratingQuestions = false
            return
        }
        
        do {
            let clarifyingViewModel = ClarifyingQuestionsViewModel(
                llmService: LLMService.shared,
                appState: appState
            )
            clarifyingQuestionsViewModel = clarifyingViewModel
            appState.clarifyingQuestionsViewModel = clarifyingViewModel
            
            try await clarifyingViewModel.startClarifyingQuestionsWorkflow(
                resume: resume,
                jobApp: jobApp,
                modelId: modelId
            )
            
            Logger.debug("🔍 After workflow completion, checking ViewModel questions:")
            Logger.debug("🔍 clarifyingViewModel.questions.count: \(clarifyingViewModel.questions.count)")
            Logger.debug("🔍 clarifyingViewModel.questions.isEmpty: \(clarifyingViewModel.questions.isEmpty)")
            
            if !clarifyingViewModel.questions.isEmpty {
                Logger.debug("Showing \(clarifyingViewModel.questions.count) clarifying questions")
                Logger.debug("🔍 About to set clarifyingQuestions binding...")
                
                // Store conversation ID for later use
                clarifyingQuestionsConversationId = clarifyingViewModel.currentConversationId
                
                // Set questions and show sheet
                clarifyingQuestions = clarifyingViewModel.questions
                Logger.debug("🔍 clarifyingQuestions binding set, count: \(clarifyingQuestions.count)")
                
                // Show the sheet
                sheets.showClarifyingQuestions = true
            } else {
                Logger.debug("AI opted to proceed without clarifying questions")
            }
            
            isGeneratingQuestions = false

        } catch {
            Logger.error("Error starting clarifying questions workflow: \(error.localizedDescription)")
            isGeneratingQuestions = false
        }
    }
    
}
