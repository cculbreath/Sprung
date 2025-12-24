//
//  ResumeReviseViewModel.swift
//  Sprung
//
//  ViewModel responsible for coordinating the resume revision workflow.
//  Delegates to specialized services for tool calling, navigation, and phase review.
//

import Foundation
import SwiftUI
import SwiftData
import SwiftOpenAI
import SwiftyJSON

/// ViewModel responsible for coordinating the resume revision workflow.
/// Acts as a facade, delegating to specialized services for different concerns.
@MainActor
@Observable
class ResumeReviseViewModel {
    // MARK: - Dependencies
    private let exportCoordinator: ResumeExportCoordinator

    // MARK: - Specialized Services
    let toolRunner: ToolConversationRunner
    let navigationManager: RevisionNavigationManager
    let phaseReviewManager: PhaseReviewManager
    private let workflowOrchestrator: RevisionWorkflowOrchestrator

    // MARK: - State
    let workflowState = RevisionWorkflowState()

    // MARK: - UI State
    var showResumeRevisionSheet: Bool = false {
        didSet {
            Logger.debug(
                "🔍 [ResumeReviseViewModel] showResumeRevisionSheet changed from \(oldValue) to \(showResumeRevisionSheet)",
                category: .ui
            )
        }
    }

    // MARK: - Convenience Accessors (for backward compatibility)

    var aiResubmit: Bool {
        get { workflowState.aiResubmit }
        set { workflowState.aiResubmit = newValue }
    }

    var currentConversationId: UUID? {
        workflowState.currentConversationId
    }

    var currentModelId: String? {
        get { workflowState.currentModelId }
        set { workflowState.currentModelId = newValue }
    }

    var isProcessingRevisions: Bool {
        workflowState.isProcessingRevisions
    }

    // MARK: - Forwarded Properties (for view compatibility)

    var resumeRevisions: [ProposedRevisionNode] {
        get { navigationManager.resumeRevisions }
        set { navigationManager.resumeRevisions = newValue }
    }

    var feedbackNodes: [FeedbackNode] {
        get { navigationManager.feedbackNodes }
        set { navigationManager.feedbackNodes = newValue }
    }

    var approvedFeedbackNodes: [FeedbackNode] {
        get { navigationManager.approvedFeedbackNodes }
        set { navigationManager.approvedFeedbackNodes = newValue }
    }

    var currentRevisionNode: ProposedRevisionNode? {
        get { navigationManager.currentRevisionNode }
        set { navigationManager.currentRevisionNode = newValue }
    }

    var currentFeedbackNode: FeedbackNode? {
        get { navigationManager.currentFeedbackNode }
        set { navigationManager.currentFeedbackNode = newValue }
    }

    var feedbackIndex: Int {
        get { navigationManager.feedbackIndex }
        set { navigationManager.feedbackIndex = newValue }
    }

    var updateNodes: [[String: Any]] {
        get { navigationManager.updateNodes }
        set { navigationManager.updateNodes = newValue }
    }

    var isEditingResponse: Bool {
        get { navigationManager.isEditingResponse }
        set { navigationManager.isEditingResponse = newValue }
    }

    var isCommenting: Bool {
        get { navigationManager.isCommenting }
        set { navigationManager.isCommenting = newValue }
    }

    var isMoreCommenting: Bool {
        get { navigationManager.isMoreCommenting }
        set { navigationManager.isMoreCommenting = newValue }
    }

    var phaseReviewState: PhaseReviewState {
        get { phaseReviewManager.phaseReviewState }
        set { phaseReviewManager.phaseReviewState = newValue }
    }

    var isHierarchicalReviewActive: Bool {
        phaseReviewManager.isHierarchicalReviewActive
    }

    var showSkillExperiencePicker: Bool {
        get { toolRunner.showSkillExperiencePicker }
        set { toolRunner.showSkillExperiencePicker = newValue }
    }

    var pendingSkillQueries: [SkillQuery] {
        get { toolRunner.pendingSkillQueries }
        set { toolRunner.pendingSkillQueries = newValue }
    }

    // MARK: - Initialization

    init(
        llmFacade: LLMFacade,
        openRouterService: OpenRouterService,
        reasoningStreamManager: ReasoningStreamManager,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfileStore: ApplicantProfileStore,
        resRefStore: ResRefStore,
        validationService: RevisionValidationService? = nil,
        streamingService: RevisionStreamingService? = nil,
        completionService: RevisionCompletionService? = nil,
        toolRegistry: ResumeToolRegistry? = nil
    ) {
        self.exportCoordinator = exportCoordinator
        let validationSvc = validationService ?? RevisionValidationService()
        let streaming = streamingService ?? RevisionStreamingService(
            llm: llmFacade,
            reasoningStreamManager: reasoningStreamManager
        )
        let completionSvc = completionService ?? RevisionCompletionService()

        // Initialize specialized services
        self.toolRunner = ToolConversationRunner(
            llm: llmFacade,
            toolRegistry: toolRegistry
        )

        self.navigationManager = RevisionNavigationManager(
            completionService: completionSvc,
            exportCoordinator: exportCoordinator
        )

        self.phaseReviewManager = PhaseReviewManager(
            llm: llmFacade,
            openRouterService: openRouterService,
            reasoningStreamManager: reasoningStreamManager,
            exportCoordinator: exportCoordinator,
            streamingService: streaming,
            applicantProfileStore: applicantProfileStore,
            resRefStore: resRefStore,
            toolRunner: self.toolRunner
        )

        self.workflowOrchestrator = RevisionWorkflowOrchestrator(
            llm: llmFacade,
            openRouterService: openRouterService,
            reasoningStreamManager: reasoningStreamManager,
            exportCoordinator: exportCoordinator,
            validationService: validationSvc,
            streamingService: streaming,
            completionService: completionSvc,
            applicantProfileStore: applicantProfileStore,
            resRefStore: resRefStore,
            toolRunner: self.toolRunner,
            phaseReviewManager: self.phaseReviewManager,
            workflowState: self.workflowState
        )

        // Set up delegates
        navigationManager.delegate = self
        phaseReviewManager.delegate = self
        workflowOrchestrator.delegate = self
    }

    // MARK: - Workflow State

    func isWorkflowBusy(_ kind: RevisionWorkflowState.WorkflowKind) -> Bool {
        workflowState.isWorkflowBusy(kind)
    }

    private func markWorkflowStarted(_ kind: RevisionWorkflowState.WorkflowKind) {
        workflowState.markWorkflowStarted(kind)
    }

    private func markWorkflowCompleted(reset: Bool) {
        workflowState.markWorkflowCompleted(reset: reset)
    }

    // MARK: - Public Interface

    /// Start a fresh revision workflow (without clarifying questions)
    func startFreshRevisionWorkflow(
        resume: Resume,
        modelId: String,
        workflow: RevisionWorkflowState.WorkflowKind
    ) async throws {
        navigationManager.reset()
        workflowState.aiResubmit = false
        try await workflowOrchestrator.startFreshRevisionWorkflow(
            resume: resume,
            modelId: modelId,
            workflow: workflow
        )
    }

    /// Continue an existing conversation and generate revisions
    func continueConversationAndGenerateRevisions(
        conversationId: UUID,
        resume: Resume,
        modelId: String
    ) async throws {
        try await workflowOrchestrator.continueConversationAndGenerateRevisions(
            conversationId: conversationId,
            resume: resume,
            modelId: modelId
        )
    }

    // MARK: - Forwarded Navigation Methods

    func saveAndNext(response: PostReviewAction, resume: Resume) {
        navigationManager.saveAndNext(response: response, resume: resume)
    }

    @discardableResult
    func nextNode(resume: Resume) -> Bool {
        navigationManager.nextNode(resume: resume)
    }

    func completeReviewWorkflow(with resume: Resume) {
        navigationManager.completeReviewWorkflow(with: resume)
    }

    func initializeUpdateNodes(for resume: Resume) {
        navigationManager.initializeUpdateNodes(for: resume)
    }

    func navigateToPrevious() {
        navigationManager.navigateToPrevious()
    }

    func navigateToNext() {
        navigationManager.navigateToNext()
    }

    func isNodeAccepted(_ feedbackNode: FeedbackNode?) -> Bool {
        navigationManager.isNodeAccepted(feedbackNode)
    }

    func isNodeRejectedWithComments(_ feedbackNode: FeedbackNode?) -> Bool {
        navigationManager.isNodeRejectedWithComments(feedbackNode)
    }

    func isNodeRejectedWithoutComments(_ feedbackNode: FeedbackNode?) -> Bool {
        navigationManager.isNodeRejectedWithoutComments(feedbackNode)
    }

    func isNodeRestored(_ feedbackNode: FeedbackNode?) -> Bool {
        navigationManager.isNodeRestored(feedbackNode)
    }

    func isNodeEdited(_ feedbackNode: FeedbackNode?) -> Bool {
        navigationManager.isNodeEdited(feedbackNode)
    }

    // MARK: - Forwarded Tool Methods

    func submitSkillExperienceResults(_ results: [SkillExperienceResult]) {
        toolRunner.submitSkillExperienceResults(results)
    }

    func cancelSkillExperienceQuery() {
        toolRunner.cancelSkillExperienceQuery()
    }

    // MARK: - Forwarded Phase Review Methods

    func sectionsWithActiveReviewPhases(for resume: Resume) -> [(section: String, phases: [TemplateManifest.ReviewPhaseConfig])] {
        phaseReviewManager.sectionsWithActiveReviewPhases(for: resume)
    }

    func startTwoRoundReview(resume: Resume, modelId: String) async throws {
        try await phaseReviewManager.startTwoRoundReview(resume: resume, modelId: modelId)
    }

    func completeCurrentPhase(resume: Resume, context: ModelContext) {
        phaseReviewManager.completeCurrentPhase(resume: resume, context: context)
    }

    func acceptCurrentItemAndMoveNext(resume: Resume, context: ModelContext) {
        phaseReviewManager.acceptCurrentItemAndMoveNext(resume: resume, context: context)
    }

    func rejectCurrentItemAndMoveNext() {
        phaseReviewManager.rejectCurrentItemAndMoveNext()
    }

    func rejectCurrentItemWithFeedback(_ feedback: String) {
        phaseReviewManager.rejectCurrentItemWithFeedback(feedback)
    }

    func acceptCurrentItemWithEdits(_ editedValue: String?, editedChildren: [String]?, resume: Resume, context: ModelContext) {
        phaseReviewManager.acceptCurrentItemWithEdits(editedValue, editedChildren: editedChildren, resume: resume, context: context)
    }

    func acceptOriginalAndMoveNext(resume: Resume, context: ModelContext) {
        phaseReviewManager.acceptOriginalAndMoveNext(resume: resume, context: context)
    }

    // MARK: - Navigation

    func goToPreviousItem() {
        phaseReviewManager.goToPreviousItem()
    }

    func goToNextItem() {
        phaseReviewManager.goToNextItem()
    }

    func goToItem(at index: Int) {
        phaseReviewManager.goToItem(at: index)
    }

    var canGoToPrevious: Bool {
        phaseReviewManager.canGoToPrevious
    }

    var canGoToNext: Bool {
        phaseReviewManager.canGoToNext
    }

    var hasItemsNeedingResubmission: Bool {
        phaseReviewManager.hasItemsNeedingResubmission
    }

    var itemsNeedingResubmission: [PhaseReviewItem] {
        phaseReviewManager.itemsNeedingResubmission
    }

    func finishPhaseReview(resume: Resume) {
        phaseReviewManager.finishPhaseReview(resume: resume)
    }

    func hasUnappliedApprovedChanges() -> Bool {
        phaseReviewManager.hasUnappliedApprovedChanges()
    }

    func applyApprovedChangesAndClose(resume: Resume, context: ModelContext) {
        phaseReviewManager.applyApprovedChangesAndClose(resume: resume, context: context)
    }

    func discardAllAndClose() {
        phaseReviewManager.discardAllAndClose()
    }
}

// MARK: - RevisionNavigationDelegate

extension ResumeReviseViewModel: RevisionNavigationDelegate {
    func showReviewSheet() {
        showResumeRevisionSheet = true
    }

    func hideReviewSheet() {
        showResumeRevisionSheet = false
    }

    func startAIResubmission(feedbackNodes: [FeedbackNode], resume: Resume) {
        feedbackIndex = 0
        workflowState.aiResubmit = true
        workflowState.workflowInProgress = true

        Task {
            do {
                Logger.debug("Starting PDF re-rendering for AI resubmission...")
                try await exportCoordinator.ensureFreshRenderedText(for: resume)
                Logger.debug("PDF rendering complete for AI resubmission")
                await workflowOrchestrator.performAIResubmission(
                    with: resume,
                    feedbackNodes: feedbackNodes,
                    exportCoordinator: exportCoordinator
                )
            } catch {
                Logger.debug("Error rendering resume for AI resubmission: \(error)")
                workflowState.aiResubmit = false
                workflowState.workflowInProgress = false
            }
        }
    }

    func setWorkflowCompleted() {
        markWorkflowCompleted(reset: true)
    }
}

// MARK: - PhaseReviewDelegate

extension ResumeReviseViewModel: PhaseReviewDelegate {
    func setConversationContext(conversationId: UUID, modelId: String) {
        workflowState.setConversationContext(conversationId: conversationId, modelId: modelId)
    }

    func setProcessingRevisions(_ processing: Bool) {
        workflowState.setProcessingRevisions(processing)
    }

    func markWorkflowStarted() {
        markWorkflowStarted(.customize)
    }
}

// MARK: - RevisionWorkflowOrchestratorDelegate

extension ResumeReviseViewModel: RevisionWorkflowOrchestratorDelegate {
    func setupRevisionsForReview(_ revisions: [ProposedRevisionNode]) async {
        Logger.debug("🔍 [ResumeReviseViewModel] setupRevisionsForReview called with \(revisions.count) revisions")
        navigationManager.setupRevisionsForReview(revisions)
        showResumeRevisionSheet = true
        workflowState.setProcessingRevisions(false)
        markWorkflowCompleted(reset: false)
    }

    func handleResubmissionResults(validatedRevisions: [ProposedRevisionNode], resubmittedNodeIds: Set<UUID>) {
        navigationManager.handleResubmissionResults(
            validatedRevisions: validatedRevisions,
            resubmittedNodeIds: resubmittedNodeIds
        )
    }
}
