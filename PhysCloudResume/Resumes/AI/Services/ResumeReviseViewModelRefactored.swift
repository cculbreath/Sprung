// PhysCloudResume/Resumes/AI/Services/ResumeReviseViewModelRefactored.swift

import Foundation
import SwiftUI
import SwiftData

/// Refactored ViewModel that delegates business logic to focused services
/// This replaces the original ResumeReviseViewModel with better separation of concerns
@MainActor
@Observable
class ResumeReviseViewModelRefactored {
    
    // MARK: - Dependencies
    private let llmService: LLMService
    private let appState: AppState
    
    // MARK: - Services
    private let workflowService: RevisionWorkflowService
    private let validationService: RevisionValidationService
    private let clarifyingQuestionsService: ClarifyingQuestionsService
    
    // MARK: - UI Delegate
    let uiViewModel: RevisionUIViewModel
    
    // MARK: - Business Logic State
    private var currentConversationId: UUID?
    private var currentModelId: String?
    private var retryCount: Int = 0
    private let maxRetries: Int = 2
    
    // MARK: - Configuration
    private let revisionTimeout: TimeInterval = 180.0
    
    init(llmService: LLMService, appState: AppState) {
        self.llmService = llmService
        self.appState = appState
        
        // Initialize services
        self.validationService = RevisionValidationService()
        self.workflowService = RevisionWorkflowService(llmService: llmService)
        self.clarifyingQuestionsService = ClarifyingQuestionsService(llmService: llmService)
        
        // Initialize UI view model
        self.uiViewModel = RevisionUIViewModel(
            workflowService: workflowService,
            clarifyingQuestionsService: clarifyingQuestionsService
        )
        
        setupAIResubmitWatcher()
    }
    
    // MARK: - Public Interface
    
    /// Start a fresh revision workflow (without clarifying questions)
    func startFreshRevisionWorkflow(resume: Resume, modelId: String) async throws {
        currentModelId = modelId
        
        do {
            let result = try await workflowService.startFreshRevisionWorkflow(
                resume: resume,
                modelId: modelId
            )
            
            currentConversationId = result.conversationId
            await uiViewModel.setupRevisionsForReview(result.revisions)
            
        } catch {
            await MainActor.run {
                uiViewModel.isProcessingRevisions = false
                uiViewModel.lastError = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Continue an existing conversation and generate revisions
    func continueConversationAndGenerateRevisions(
        conversationId: UUID,
        resume: Resume,
        modelId: String
    ) async throws {
        currentConversationId = conversationId
        currentModelId = modelId
        
        await uiViewModel.continueConversationAndGenerateRevisions(
            conversationId: conversationId,
            resume: resume,
            modelId: modelId
        )
    }
    
    /// Generate clarifying questions for the resume revision
    func requestClarifyingQuestions(
        resume: Resume,
        query: ResumeApiQuery,
        modelId: String
    ) async throws -> ClarifyingQuestionsRequest? {
        return await uiViewModel.requestClarifyingQuestions(
            resume: resume,
            query: query,
            modelId: modelId
        )
    }
    
    /// Apply only accepted changes to the resume tree structure
    func applyAcceptedChanges(feedbackNodes: [FeedbackNode], to resume: Resume) {
        feedbackNodes.applyAcceptedChanges(to: resume)
    }
    
    // MARK: - AI Resubmission Handling
    
    private func setupAIResubmitWatcher() {
        // Monitor aiResubmit changes to trigger resubmission workflow
    }
    
    func handleAIResubmitChange() {
        guard uiViewModel.aiResubmit else { return }
        
        Logger.debug("🔄 AI resubmit triggered - state updated for UI")
        uiViewModel.isProcessingRevisions = true
    }
    
    func performAIResubmission(with resume: Resume) async {
        guard let conversationId = currentConversationId,
              let modelId = currentModelId else {
            await MainActor.run {
                uiViewModel.aiResubmit = false
                uiViewModel.lastError = "No conversation or model available for AI resubmission"
            }
            return
        }
        
        await uiViewModel.performAIResubmission(
            with: resume,
            conversationId: conversationId,
            modelId: modelId
        )
    }
    
    // MARK: - Workflow Management
    
    func resetWorkflowState() {
        Logger.debug("🔄 Resetting revision workflow state")
        
        if let conversationId = currentConversationId {
            llmService.clearConversation(id: conversationId)
        }
        
        currentConversationId = nil
        currentModelId = nil
        retryCount = 0
        
        uiViewModel.resetWorkflowState()
    }
    
    // MARK: - Navigation Delegation
    
    func saveAndNext(response: PostReviewAction, resume: Resume) {
        uiViewModel.saveAndNext(response: response, resume: resume)
    }
    
    func nextNode(resume: Resume) {
        uiViewModel.nextNode(resume: resume)
    }
    
    func navigateToPrevious() {
        uiViewModel.navigateToPrevious()
    }
    
    func navigateToNext() {
        uiViewModel.navigateToNext()
    }
    
    func initializeUpdateNodes(for resume: Resume) {
        uiViewModel.initializeUpdateNodes(for: resume)
    }
    
    // MARK: - UI State Queries (Delegated)
    
    func isNodeAccepted(_ feedbackNode: FeedbackNode?) -> Bool {
        return uiViewModel.isNodeAccepted(feedbackNode)
    }
    
    func isNodeRejectedWithComments(_ feedbackNode: FeedbackNode?) -> Bool {
        return uiViewModel.isNodeRejectedWithComments(feedbackNode)
    }
    
    func isNodeRejectedWithoutComments(_ feedbackNode: FeedbackNode?) -> Bool {
        return uiViewModel.isNodeRejectedWithoutComments(feedbackNode)
    }
    
    func isNodeRestored(_ feedbackNode: FeedbackNode?) -> Bool {
        return uiViewModel.isNodeRestored(feedbackNode)
    }
    
    func isNodeEdited(_ feedbackNode: FeedbackNode?) -> Bool {
        return uiViewModel.isNodeEdited(feedbackNode)
    }
    
    func isChangeRequested(_ feedbackNode: FeedbackNode?) -> Bool {
        return uiViewModel.isChangeRequested(feedbackNode)
    }
    
    // MARK: - Computed Properties for UI Binding
    
    var showResumeRevisionSheet: Bool {
        get { uiViewModel.showResumeRevisionSheet }
        set { uiViewModel.showResumeRevisionSheet = newValue }
    }
    
    var resumeRevisions: [ProposedRevisionNode] {
        get { uiViewModel.resumeRevisions }
        set { uiViewModel.resumeRevisions = newValue }
    }
    
    var feedbackNodes: [FeedbackNode] {
        get { uiViewModel.feedbackNodes }
        set { uiViewModel.feedbackNodes = newValue }
    }
    
    var currentRevisionNode: ProposedRevisionNode? {
        get { uiViewModel.currentRevisionNode }
        set { uiViewModel.currentRevisionNode = newValue }
    }
    
    var currentFeedbackNode: FeedbackNode? {
        get { uiViewModel.currentFeedbackNode }
        set { uiViewModel.currentFeedbackNode = newValue }
    }
    
    var aiResubmit: Bool {
        get { uiViewModel.aiResubmit }
        set { uiViewModel.aiResubmit = newValue }
    }
    
    var feedbackIndex: Int {
        get { uiViewModel.feedbackIndex }
        set { uiViewModel.feedbackIndex = newValue }
    }
    
    var updateNodes: [[String: Any]] {
        get { uiViewModel.updateNodes }
        set { uiViewModel.updateNodes = newValue }
    }
    
    var isEditingResponse: Bool {
        get { uiViewModel.isEditingResponse }
        set { uiViewModel.isEditingResponse = newValue }
    }
    
    var isCommenting: Bool {
        get { uiViewModel.isCommenting }
        set { uiViewModel.isCommenting = newValue }
    }
    
    var isMoreCommenting: Bool {
        get { uiViewModel.isMoreCommenting }
        set { uiViewModel.isMoreCommenting = newValue }
    }
    
    var isProcessingRevisions: Bool {
        get { uiViewModel.isProcessingRevisions }
        set { uiViewModel.isProcessingRevisions = newValue }
    }
    
    var lastError: String? {
        get { uiViewModel.lastError }
        set { uiViewModel.lastError = newValue }
    }
}