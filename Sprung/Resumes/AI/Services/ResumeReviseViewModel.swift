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
    enum RevisionWorkflowKind {
        case customize
        case clarifying
    }

    // MARK: - Dependencies
    private let llm: LLMFacade
    let openRouterService: OpenRouterService
    private let reasoningStreamManager: ReasoningStreamManager
    private let exportCoordinator: ResumeExportCoordinator
    private let validationService: RevisionValidationService
    private let streamingService: RevisionStreamingService
    private let completionService: RevisionCompletionService
    private let applicantProfileStore: ApplicantProfileStore
    private let resRefStore: ResRefStore

    // MARK: - Specialized Services
    let toolRunner: ToolConversationRunner
    let navigationManager: RevisionNavigationManager
    let phaseReviewManager: PhaseReviewManager

    // MARK: - UI State
    var showResumeRevisionSheet: Bool = false {
        didSet {
            Logger.debug(
                "🔍 [ResumeReviseViewModel] showResumeRevisionSheet changed from \(oldValue) to \(showResumeRevisionSheet)",
                category: .ui
            )
        }
    }

    var aiResubmit: Bool = false
    private(set) var activeWorkflow: RevisionWorkflowKind?
    private var workflowInProgress: Bool = false

    // MARK: - Business Logic State
    private(set) var currentConversationId: UUID?
    var currentModelId: String?
    private(set) var isProcessingRevisions: Bool = false

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
        self.llm = llmFacade
        self.openRouterService = openRouterService
        self.reasoningStreamManager = reasoningStreamManager
        self.exportCoordinator = exportCoordinator
        self.validationService = validationService ?? RevisionValidationService()
        let streaming = streamingService ?? RevisionStreamingService(
            llm: llmFacade,
            reasoningStreamManager: reasoningStreamManager
        )
        self.streamingService = streaming
        self.completionService = completionService ?? RevisionCompletionService()
        self.applicantProfileStore = applicantProfileStore
        self.resRefStore = resRefStore

        // Initialize specialized services
        self.toolRunner = ToolConversationRunner(
            llm: llmFacade,
            toolRegistry: toolRegistry
        )

        self.navigationManager = RevisionNavigationManager(
            completionService: self.completionService,
            exportCoordinator: exportCoordinator
        )

        self.phaseReviewManager = PhaseReviewManager(
            llm: llmFacade,
            openRouterService: openRouterService,
            reasoningStreamManager: reasoningStreamManager,
            exportCoordinator: exportCoordinator,
            streamingService: streaming,
            applicantProfileStore: applicantProfileStore,
            resRefStore: resRefStore
        )

        // Set up delegates
        navigationManager.delegate = self
        phaseReviewManager.delegate = self
    }

    // MARK: - Workflow State

    func isWorkflowBusy(_ kind: RevisionWorkflowKind) -> Bool {
        guard activeWorkflow == kind else { return false }
        return workflowInProgress || aiResubmit
    }

    private func markWorkflowStarted(_ kind: RevisionWorkflowKind) {
        activeWorkflow = kind
        workflowInProgress = true
    }

    private func markWorkflowCompleted(reset: Bool) {
        workflowInProgress = false
        if reset {
            activeWorkflow = nil
        }
    }

    // MARK: - Public Interface

    /// Start a fresh revision workflow (without clarifying questions)
    func startFreshRevisionWorkflow(
        resume: Resume,
        modelId: String,
        workflow: RevisionWorkflowKind
    ) async throws {
        // Check if any sections have multi-phase review configured
        let sectionsWithPhases = phaseReviewManager.sectionsWithActiveReviewPhases(for: resume)
        if let firstSection = sectionsWithPhases.first {
            Logger.info("🎯 Using multi-phase review for '\(firstSection.section)' with \(firstSection.phases.count) phases")
            try await phaseReviewManager.startPhaseReview(
                resume: resume,
                section: firstSection.section,
                phases: firstSection.phases,
                modelId: modelId
            )
            return
        }

        markWorkflowStarted(workflow)
        navigationManager.reset()
        aiResubmit = false
        isProcessingRevisions = true

        do {
            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                allResRefs: resRefStore.resRefs,
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )

            let systemPrompt = query.genericSystemMessage.textContent
            let userPrompt = await query.wholeResumeQueryString()

            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false

            Logger.debug("🤖 [startFreshRevisionWorkflow] Model: \(modelId)")
            Logger.debug("🤖 [startFreshRevisionWorkflow] Supports reasoning: \(supportsReasoning)")

            let useTools = toolRunner.shouldUseTools(modelId: modelId, openRouterService: openRouterService)
            Logger.debug("🤖 [startFreshRevisionWorkflow] Use tools: \(useTools)")

            if !supportsReasoning {
                reasoningStreamManager.hideAndClear()
            }

            let revisions: RevisionsContainer

            if useTools && !supportsReasoning {
                Logger.info("🔧 [Tools] Using tool-enabled conversation for revision generation: \(modelId)")
                self.currentModelId = modelId

                let toolSystemPrompt = systemPrompt + """

                    You have access to the `query_user_experience_level` tool.
                    Use this tool when you encounter skills in the job description that are adjacent to
                    the user's background but not explicitly mentioned in their resume. For example,
                    if the user has React experience and the job mentions React Native, query their
                    React Native experience level before making assumptions.

                    If the tool returns an error indicating the user skipped the query, proceed with
                    your best judgment based on available information.

                    After gathering any needed information via tools, provide your revision suggestions
                    in the specified JSON format.
                    """

                let finalResponse = try await toolRunner.runConversation(
                    systemPrompt: toolSystemPrompt,
                    userPrompt: userPrompt + "\n\nPlease provide the revision suggestions in the specified JSON format.",
                    modelId: modelId,
                    resume: resume,
                    jobApp: nil
                )

                revisions = try toolRunner.parseRevisionsFromResponse(finalResponse)

            } else if supportsReasoning {
                Logger.info("🧠 Using streaming with reasoning for revision generation: \(modelId)")
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(
                    effort: userEffort,
                    includeReasoning: true
                )

                let result = try await streamingService.startConversationStreaming(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )

                self.currentConversationId = result.conversationId
                self.currentModelId = modelId
                revisions = result.revisions

            } else {
                Logger.info("📝 Using non-streaming structured output for revision generation: \(modelId)")

                let (conversationId, _) = try await llm.startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId
                )

                self.currentConversationId = conversationId
                self.currentModelId = modelId

                revisions = try await llm.continueConversationStructured(
                    userMessage: "Please provide the revision suggestions in the specified JSON format.",
                    modelId: modelId,
                    conversationId: conversationId,
                    as: RevisionsContainer.self,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
            }

            let validatedRevisions = validationService.validateRevisions(revisions.revArray, for: resume)
            await setupRevisionsForReview(validatedRevisions)

        } catch {
            isProcessingRevisions = false
            markWorkflowCompleted(reset: true)
            throw error
        }
    }

    /// Continue an existing conversation and generate revisions
    func continueConversationAndGenerateRevisions(
        conversationId: UUID,
        resume: Resume,
        modelId: String
    ) async throws {
        markWorkflowStarted(.clarifying)
        currentConversationId = conversationId
        currentModelId = modelId
        isProcessingRevisions = true

        do {
            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                allResRefs: resRefStore.resRefs,
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )

            let revisionRequestPrompt = await query.multiTurnRevisionPrompt()

            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false

            Logger.debug("🤖 [continueConversationAndGenerateRevisions] Model: \(modelId)")
            Logger.debug("🤖 [continueConversationAndGenerateRevisions] Supports reasoning: \(supportsReasoning)")

            if supportsReasoning {
                reasoningStreamManager.startReasoning(modelName: modelId)
            } else {
                reasoningStreamManager.hideAndClear()
            }

            let revisions: RevisionsContainer

            if supportsReasoning {
                Logger.info("🧠 Using streaming with reasoning for revision continuation: \(modelId)")
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(
                    effort: userEffort,
                    includeReasoning: true
                )

                revisions = try await streamingService.continueConversationStreaming(
                    userMessage: revisionRequestPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
            } else {
                Logger.info("📝 Using non-streaming structured output for revision continuation: \(modelId)")
                revisions = try await llm.continueConversationStructured(
                    userMessage: revisionRequestPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    as: RevisionsContainer.self,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
            }

            let validatedRevisions = validationService.validateRevisions(revisions.revArray, for: resume)
            await setupRevisionsForReview(validatedRevisions)
            Logger.debug("✅ Conversation handoff complete: \(validatedRevisions.count) revisions ready for review")

        } catch {
            Logger.error("Error continuing conversation for revisions: \(error.localizedDescription)")
            isProcessingRevisions = false
            markWorkflowCompleted(reset: true)
            throw error
        }
    }

    /// Set up revisions for UI review
    @MainActor
    private func setupRevisionsForReview(_ revisions: [ProposedRevisionNode]) async {
        Logger.debug("🔍 [ResumeReviseViewModel] setupRevisionsForReview called with \(revisions.count) revisions")

        navigationManager.setupRevisionsForReview(revisions)

        reasoningStreamManager.hideAndClear()
        Logger.debug("🔍 [ResumeReviseViewModel] Setting showResumeRevisionSheet = true")
        showResumeRevisionSheet = true
        isProcessingRevisions = false
        markWorkflowCompleted(reset: false)
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

    func startPhaseReview(
        resume: Resume,
        section: String,
        phases: [TemplateManifest.ReviewPhaseConfig],
        modelId: String
    ) async throws {
        try await phaseReviewManager.startPhaseReview(
            resume: resume,
            section: section,
            phases: phases,
            modelId: modelId
        )
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
        aiResubmit = true
        workflowInProgress = true

        Task {
            do {
                Logger.debug("Starting PDF re-rendering for AI resubmission...")
                try await exportCoordinator.ensureFreshRenderedText(for: resume)
                Logger.debug("PDF rendering complete for AI resubmission")
                await performAIResubmission(with: resume)
            } catch {
                Logger.debug("Error rendering resume for AI resubmission: \(error)")
                aiResubmit = false
                workflowInProgress = false
            }
        }
    }

    func setWorkflowCompleted() {
        markWorkflowCompleted(reset: true)
    }

    /// Perform the actual AI resubmission with feedback nodes requiring revision
    @MainActor
    private func performAIResubmission(with resume: Resume) async {
        guard let conversationId = currentConversationId else {
            Logger.error("No conversation ID available for AI resubmission")
            aiResubmit = false
            return
        }

        guard let modelId = currentModelId else {
            Logger.error("No model available for AI resubmission")
            aiResubmit = false
            return
        }

        let model = openRouterService.findModel(id: modelId)
        let supportsReasoning = model?.supportsReasoning ?? false

        if supportsReasoning {
            Logger.debug("🔍 Temporarily hiding review sheet for reasoning modal")
            showResumeRevisionSheet = false
        }

        do {
            let nodesToResubmit = feedbackNodes.filter { node in
                let aiActions: Set<PostReviewAction> = [.revise, .mandatedChange, .mandatedChangeNoComment, .rewriteNoComment]
                return aiActions.contains(node.actionRequested)
            }

            Logger.debug("🔄 Resubmitting \(nodesToResubmit.count) nodes to AI")

            let result = completionService.completeReviewWorkflow(
                feedbackNodes: nodesToResubmit,
                approvedFeedbackNodes: [],
                resume: resume,
                exportCoordinator: exportCoordinator
            )

            guard case .requiresResubmission(_, let revisionPrompt) = result else {
                Logger.error("Expected resubmission result but got finished")
                aiResubmit = false
                workflowInProgress = false
                showResumeRevisionSheet = true
                return
            }

            let revisions: RevisionsContainer

            if supportsReasoning {
                Logger.info("🧠 Using streaming with reasoning for AI resubmission: \(modelId)")
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(
                    effort: userEffort,
                    includeReasoning: true
                )

                revisions = try await streamingService.continueConversationStreaming(
                    userMessage: revisionPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
            } else {
                revisions = try await llm.continueConversationStructured(
                    userMessage: revisionPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    as: RevisionsContainer.self,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
            }

            let validatedRevisions = validationService.validateRevisions(revisions.revArray, for: resume)
            let resubmittedNodeIds = Set(nodesToResubmit.map { $0.id })

            navigationManager.handleResubmissionResults(
                validatedRevisions: validatedRevisions,
                resubmittedNodeIds: resubmittedNodeIds
            )

            aiResubmit = false
            workflowInProgress = false

            if !resumeRevisions.isEmpty {
                if supportsReasoning {
                    Logger.debug("🔍 Showing review sheet again after reasoning modal")
                } else {
                    Logger.debug("🔍 Reopening review sheet after resubmission (non-reasoning model)")
                }
                showResumeRevisionSheet = true
            }

            Logger.debug("✅ AI resubmission complete: \(validatedRevisions.count) new revisions ready for review")

        } catch {
            Logger.error("Error in AI resubmission: \(error.localizedDescription)")
            aiResubmit = false
            workflowInProgress = false
            showResumeRevisionSheet = true
        }
    }
}

// MARK: - PhaseReviewDelegate

extension ResumeReviseViewModel: PhaseReviewDelegate {
    func setConversationContext(conversationId: UUID, modelId: String) {
        self.currentConversationId = conversationId
        self.currentModelId = modelId
    }

    func setProcessingRevisions(_ processing: Bool) {
        isProcessingRevisions = processing
    }

    func markWorkflowStarted() {
        markWorkflowStarted(.customize)
    }
}
