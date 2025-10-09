// PhysCloudResume/Resumes/AI/Views/ResumeReviewViewModel.swift

import Foundation
import SwiftUI

@MainActor
@Observable
class ResumeReviewViewModel {
    // MARK: - State Properties
    
    // General review state
    private(set) var reviewResponseText: String = ""
    private(set) var isProcessingGeneral: Bool = false
    private(set) var generalError: String? = nil
    
    // Fix Overflow state
    private(set) var fixOverflowStatusMessage: String = ""
    private(set) var fixOverflowChangeMessage: String = ""
    private(set) var isProcessingFixOverflow: Bool = false
    private(set) var fixOverflowError: String? = nil
    private(set) var currentOverflowLineCount: Int = 0
    
    // MARK: - Reasoning Stream State (now uses global manager)
    // reasoningStreamManager is accessed via appState.globalReasoningStreamManager
    
    // Services
    private var reviewService: ResumeReviewService?
    private var fixOverflowService: FixOverflowService?
    private var reorderSkillsService: ReorderSkillsService?
    
    // MARK: - Initialization
    
    func initialize(llmFacade: LLMFacade, exportCoordinator: ResumeExportCoordinator) {
        reviewService = ResumeReviewService(llmFacade: llmFacade)
        reviewService?.initialize()
        if let svc = reviewService {
            fixOverflowService = FixOverflowService(reviewService: svc, exportCoordinator: exportCoordinator)
            reorderSkillsService = ReorderSkillsService(reviewService: svc, exportCoordinator: exportCoordinator)
        } else {
            Logger.error("ResumeReviewViewModel: reviewService not initialized; dependent services unavailable")
        }
        resetChangeMessage()
    }
    
    // MARK: - Public Methods
    
    func handleSubmit(
        reviewType: ResumeReviewType,
        resume: Resume,
        selectedModel: String,
        customOptions: CustomReviewOptions?,
        allowEntityMerge: Bool,
        appState: AppState
    ) {
        resetState()
        
        switch reviewType {
        case .fixOverflow:
            Task {
                await performFixOverflow(resume: resume, allowEntityMerge: allowEntityMerge, selectedModel: selectedModel, appState: appState)
            }
        case .reorderSkills:
            Task {
                await performReorderSkills(resume: resume, selectedModel: selectedModel, appState: appState)
            }
        default:
            performGeneralReview(
                reviewType: reviewType,
                resume: resume,
                selectedModel: selectedModel,
                customOptions: customOptions
            )
        }
    }
    
    func cancelRequest() {
        reviewService?.cancelRequest()
        isProcessingGeneral = false
        isProcessingFixOverflow = false
        fixOverflowStatusMessage = "Operation stopped by user."
    }
    
    func resetOnReviewTypeChange() {
        reviewResponseText = ""
        fixOverflowStatusMessage = ""
        isProcessingGeneral = false
        isProcessingFixOverflow = false
        generalError = nil
        fixOverflowError = nil
    }
    
    func resetChangeMessage() {
        fixOverflowChangeMessage = ""
    }
    
    // MARK: - Private Methods
    
    private func resetState() {
        reviewResponseText = ""
        fixOverflowStatusMessage = ""
        fixOverflowChangeMessage = ""
        generalError = nil
        fixOverflowError = nil
    }
    
    private func performGeneralReview(
        reviewType: ResumeReviewType,
        resume: Resume,
        selectedModel: String,
        customOptions: CustomReviewOptions?
    ) {
        isProcessingGeneral = true
        reviewResponseText = "Submitting request..."
        
        reviewService?.sendReviewRequest(
            reviewType: reviewType,
            resume: resume,
            modelId: selectedModel,
            customOptions: reviewType == .custom ? customOptions : nil,
            onProgress: { [weak self] contentChunk in
                Task { @MainActor in
                    guard let self = self else { return }
                    if self.reviewResponseText == "Submitting request..." { 
                        self.reviewResponseText = "" 
                    }
                    self.reviewResponseText += contentChunk
                }
            },
            onComplete: { [weak self] result in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isProcessingGeneral = false
                    switch result {
                    case let .success(finalMessage):
                        if self.reviewResponseText == "Submitting request..." || self.reviewResponseText.isEmpty {
                            self.reviewResponseText = finalMessage
                        }
                        if self.reviewResponseText.isEmpty {
                            self.reviewResponseText = "Review complete. No specific feedback provided."
                        }
                    case let .failure(error):
                        self.handleGeneralError(error)
                        if self.reviewResponseText == "Submitting request..." || !self.reviewResponseText.isEmpty {
                            self.reviewResponseText = ""
                        }
                    }
                }
            }
        )
    }
    
    private func handleGeneralError(_ error: Error) {
        if let nsError = error as NSError? {
            if nsError.domain == "OpenAIAPI" {
                generalError = "API Error: \(nsError.localizedDescription)"
            } else if let errorInfo = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                generalError = "Error: \(errorInfo)\nPlease try again or select a different model in Settings."
            } else {
                generalError = "Error: \(error.localizedDescription)"
            }
        } else {
            generalError = "Error: \(error.localizedDescription)"
        }
    }
    
    private func performFixOverflow(resume: Resume, allowEntityMerge: Bool, selectedModel: String, appState: AppState) async {
        isProcessingFixOverflow = true
        fixOverflowStatusMessage = "Starting skills optimization..."
        
        // Check if model supports reasoning and prepare callback  
        let model = appState.openRouterService.findModel(id: selectedModel)
        let supportsReasoning = model?.supportsReasoning ?? false
        let reasoningCallback: ((String) -> Void)? = supportsReasoning ? { reasoningContent in
            Task { @MainActor in
                appState.globalReasoningStreamManager.reasoningText += reasoningContent
            }
        } : nil
        
        // Start reasoning stream if applicable
        if supportsReasoning {
            appState.globalReasoningStreamManager.startReasoning(modelName: selectedModel)
        }
        
        let result = await fixOverflowService?.performFixOverflow(
            resume: resume,
            allowEntityMerge: allowEntityMerge,
            selectedModel: selectedModel,
            maxIterations: UserDefaults.standard.integer(forKey: "fixOverflowMaxIterations") == 0 ? 3 : UserDefaults.standard.integer(forKey: "fixOverflowMaxIterations"),
            supportsReasoning: supportsReasoning,
            onStatusUpdate: { [weak self] status in
                Task { @MainActor in
                    self?.fixOverflowStatusMessage = status.statusMessage
                    self?.fixOverflowChangeMessage = status.changeMessage
                    self?.currentOverflowLineCount = status.overflowLineCount
                }
            },
            onReasoningUpdate: reasoningCallback
        )
        
        switch result {
        case .success(let finalStatus):
            fixOverflowStatusMessage = finalStatus
        case .failure(let error):
            fixOverflowError = error.localizedDescription
        case .none:
            fixOverflowError = "Fix Overflow service unavailable."
        }
        
        // Complete reasoning stream
        if supportsReasoning {
            appState.globalReasoningStreamManager.stopStream()
        }
        
        isProcessingFixOverflow = false
    }
    
    private func performReorderSkills(resume: Resume, selectedModel: String, appState: AppState) async {
        isProcessingFixOverflow = true
        fixOverflowStatusMessage = "Starting skills reordering..."
        
        let result = await reorderSkillsService?.performReorderSkills(
            resume: resume,
            selectedModel: selectedModel,
            appState: appState
        ) { [weak self] status in
            Task { @MainActor in
                self?.fixOverflowStatusMessage = status.statusMessage
                self?.fixOverflowChangeMessage = status.changeMessage
            }
        }
        
        switch result {
        case .success(let finalStatus):
            fixOverflowStatusMessage = finalStatus
        case .failure(let error):
            fixOverflowError = error.localizedDescription
        case .none:
            fixOverflowError = "Reorder Skills service unavailable."
        }
        
        isProcessingFixOverflow = false
    }
}
