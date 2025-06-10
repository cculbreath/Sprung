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
    
    var body: some View {
        Button(action: {
            selectedTab = .resume
            clarifyingQuestions = []
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
            
            isGeneratingQuestions = false

        } catch {
            Logger.error("Error starting clarifying questions workflow: \(error.localizedDescription)")
            isGeneratingQuestions = false
        }
    }
    
    @MainActor
    private func processClarifyingQuestionsAnswers(answers: [QuestionAnswer]) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            return
        }
        
        do {
            guard let clarifyingViewModel = clarifyingQuestionsViewModel else {
                Logger.error("ClarifyingQuestionsViewModel not available for processing answers")
                return
            }
            
            guard let resumeViewModel = resumeReviseViewModel else {
                Logger.error("ResumeReviseViewModel not available for handoff")
                return
            }
            
            try await clarifyingViewModel.processAnswersAndHandoffConversation(
                answers: answers,
                resume: resume,
                resumeReviseViewModel: resumeViewModel
            )
            
            Logger.debug("✅ Clarifying questions processed and handed off to ResumeReviseViewModel")
            
        } catch {
            Logger.error("Error processing clarifying questions answers: \\(error.localizedDescription)")
        }
        
        isGeneratingQuestions = false
    }
}
