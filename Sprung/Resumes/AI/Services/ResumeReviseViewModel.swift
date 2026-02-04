//
//  ResumeReviseViewModel.swift
//  Sprung
//
//  ViewModel responsible for coordinating the resume revision workflow.
//  Uses parallel LLM execution with accumulating review queue.
//

import Foundation
import SwiftUI
import SwiftData
import SwiftOpenAI
import SwiftyJSON

/// ViewModel responsible for coordinating the resume revision workflow.
/// Uses parallel task execution with SGM-style accumulating review queue.
@MainActor
@Observable
class ResumeReviseViewModel {
    // MARK: - Dependencies
    private let exportCoordinator: ResumeExportCoordinator
    let openRouterService: OpenRouterService

    // MARK: - Specialized Services (Public for direct access)
    let toolRunner: ToolConversationRunner
    let phaseReviewManager: PhaseReviewManager
    let workflowOrchestrator: RevisionWorkflowOrchestrator

    // MARK: - State
    let workflowState = RevisionWorkflowState()

    // MARK: - UI State
    /// Shows the parallel review queue UI
    var showParallelReviewQueueSheet: Bool = false

    /// The review queue for the parallel workflow (exposed for UI binding)
    var parallelReviewQueue: CustomizationReviewQueue? {
        workflowOrchestrator.reviewQueue
    }

    // MARK: - Convenience Accessors

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
        knowledgeCardStore: KnowledgeCardStore,
        coverRefStore: CoverRefStore,
        guidanceStore: InferenceGuidanceStore? = nil,
        skillStore: SkillStore? = nil,
        titleSetStore: TitleSetStore? = nil,
        streamingService: RevisionStreamingService? = nil,
        toolRegistry: ResumeToolRegistry? = nil
    ) {
        self.exportCoordinator = exportCoordinator
        self.openRouterService = openRouterService
        let streaming = streamingService ?? RevisionStreamingService(
            llm: llmFacade,
            reasoningStreamManager: reasoningStreamManager
        )

        // Initialize specialized services
        self.toolRunner = ToolConversationRunner(
            llm: llmFacade,
            toolRegistry: toolRegistry
        )

        self.phaseReviewManager = PhaseReviewManager(
            llm: llmFacade,
            openRouterService: openRouterService,
            reasoningStreamManager: reasoningStreamManager,
            exportCoordinator: exportCoordinator,
            streamingService: streaming,
            applicantProfileStore: applicantProfileStore,
            knowledgeCardStore: knowledgeCardStore,
            toolRunner: self.toolRunner,
            guidanceStore: guidanceStore,
            coverRefStore: coverRefStore
        )

        self.workflowOrchestrator = RevisionWorkflowOrchestrator(
            llm: llmFacade,
            openRouterService: openRouterService,
            reasoningStreamManager: reasoningStreamManager,
            exportCoordinator: exportCoordinator,
            streamingService: streaming,
            applicantProfileStore: applicantProfileStore,
            knowledgeCardStore: knowledgeCardStore,
            toolRunner: self.toolRunner,
            phaseReviewManager: self.phaseReviewManager,
            guidanceStore: guidanceStore,
            skillStore: skillStore,
            titleSetStore: titleSetStore,
            workflowState: self.workflowState
        )

        // Set up delegates
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

    // MARK: - Parallel Workflow

    /// Start the parallel revision workflow
    /// - Parameters:
    ///   - resume: The resume to customize
    ///   - modelId: The LLM model ID (from user selection)
    ///   - clarifyingQA: Optional clarifying questions and answers to prepend to preamble
    ///   - coverRefStore: Cover ref store for writing samples
    func startParallelRevisionWorkflow(
        resume: Resume,
        modelId: String,
        clarifyingQA: [(ClarifyingQuestion, QuestionAnswer)]? = nil,
        coverRefStore: CoverRefStore
    ) async throws {
        workflowState.aiResubmit = false
        try await workflowOrchestrator.startParallelWorkflow(
            resume: resume,
            modelId: modelId,
            clarifyingQA: clarifyingQA,
            coverRefStore: coverRefStore
        )
    }

    /// Complete the current phase, apply approved changes, and advance to the next phase or finalize
    func completeCurrentPhaseAndAdvance(resume: Resume, context: ModelContext) async throws {
        try await workflowOrchestrator.completeCurrentPhaseAndAdvance(resume: resume, context: context)
    }

    /// Apply all approved parallel changes and close the workflow
    func applyApprovedParallelChangesAndClose(resume: Resume, context: ModelContext) {
        workflowOrchestrator.applyApprovedAndClose(resume: resume, context: context)
    }

    /// Discard all parallel changes and close the workflow
    func discardParallelChangesAndClose() {
        workflowOrchestrator.discardAndClose()
    }

    /// Whether there are unapplied approved changes in the parallel review queue
    func hasUnappliedParallelApprovedChanges() -> Bool {
        workflowOrchestrator.hasUnappliedApprovedChanges()
    }

    /// Whether Phase 2 is still pending
    var hasPhase2Pending: Bool {
        workflowOrchestrator.hasPhase2Pending
    }

    /// Current phase number (1 or 2) for UI display
    var currentPhaseNumber: Int {
        workflowOrchestrator.currentPhaseNumber
    }

    /// Total phases (1 or 2) for UI display
    var totalPhases: Int {
        workflowOrchestrator.totalPhases
    }

    // MARK: - Forwarded Tool Methods

    func submitSkillExperienceResults(_ results: [SkillExperienceResult]) {
        toolRunner.submitSkillExperienceResults(results)
    }

    func cancelSkillExperienceQuery() {
        toolRunner.cancelSkillExperienceQuery()
    }

    // MARK: - Forwarded Phase Review Methods

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

    var canGoToPrevious: Bool {
        phaseReviewManager.canGoToPrevious
    }

    var canGoToNext: Bool {
        phaseReviewManager.canGoToNext
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

    func showReviewSheet() {
        showParallelReviewQueueSheet = true
    }

    func hideReviewSheet() {
        showParallelReviewQueueSheet = false
    }

    func setWorkflowCompleted() {
        markWorkflowCompleted(reset: true)
    }
}

// MARK: - RevisionWorkflowOrchestratorDelegate

extension ResumeReviseViewModel: RevisionWorkflowOrchestratorDelegate {
    func showParallelReviewQueue() {
        showParallelReviewQueueSheet = true
    }

    func hideParallelReviewQueue() {
        showParallelReviewQueueSheet = false
    }
}
