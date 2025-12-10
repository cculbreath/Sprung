//
//  ResumeReviseViewModel.swift
//  Sprung
//
//
import Foundation
import SwiftUI
import SwiftData
/// ViewModel responsible for managing the complex resume revision workflow
/// Extracts business logic from AiCommsView to provide clean separation of concerns
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
    // MARK: - UI State (ViewModel Layer)
    var showResumeRevisionSheet: Bool = false {
        didSet {
            Logger.debug(
                "🔍 [ResumeReviseViewModel] showResumeRevisionSheet changed from \(oldValue) to \(showResumeRevisionSheet)",
                category: .ui
            )
        }
    }
    var resumeRevisions: [ProposedRevisionNode] = []
    var feedbackNodes: [FeedbackNode] = []
    var approvedFeedbackNodes: [FeedbackNode] = [] // Store approved feedback for multi-round workflows
    var currentRevisionNode: ProposedRevisionNode?
    var currentFeedbackNode: FeedbackNode?
    var aiResubmit: Bool = false
    private(set) var activeWorkflow: RevisionWorkflowKind?
    private var workflowInProgress: Bool = false
    // Review workflow navigation state (moved from ReviewView)
    var feedbackIndex: Int = 0
    var updateNodes: [[String: Any]] = []
    var isEditingResponse: Bool = false
    var isCommenting: Bool = false
    var isMoreCommenting: Bool = false

    // MARK: - Two-Phase Hierarchical Review State

    /// Current phase in the hierarchical skills review workflow
    var currentRevisionPhase: RevisionPhase = .categoryStructure

    /// Category-level revisions from Phase 1 (structure review)
    var categoryRevisions: [CategoryRevisionNode] = []

    /// Categories pending Phase 2 keyword review (populated after Phase 1 completion)
    var pendingCategoryIds: [String] = []

    /// Index of the current category being reviewed in Phase 2
    var currentCategoryIndex: Int = 0

    /// Current keywords revision container for Phase 2
    var currentKeywordsRevision: KeywordsRevisionContainer?

    /// Approved category structure changes (Phase 1)
    var approvedCategoryChanges: [CategoryRevisionNode] = []

    /// Approved keywords changes (Phase 2) - keyed by category ID
    var approvedKeywordsChanges: [String: KeywordsRevisionContainer] = [:]

    /// Flag indicating if we're in the hierarchical review workflow
    var isHierarchicalReviewActive: Bool = false
    // MARK: - Business Logic State
    private var currentConversationId: UUID?
    var currentModelId: String? // Make currentModelId accessible to views
    private(set) var isProcessingRevisions: Bool = false
    private var isCompletingReview: Bool = false
    init(
        llmFacade: LLMFacade,
        openRouterService: OpenRouterService,
        reasoningStreamManager: ReasoningStreamManager,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfileStore: ApplicantProfileStore,
        validationService: RevisionValidationService? = nil,
        streamingService: RevisionStreamingService? = nil,
        completionService: RevisionCompletionService? = nil
    ) {
        self.llm = llmFacade
        self.openRouterService = openRouterService
        self.reasoningStreamManager = reasoningStreamManager
        self.exportCoordinator = exportCoordinator
        self.validationService = validationService ?? RevisionValidationService()
        self.streamingService = streamingService ?? RevisionStreamingService(
            llm: llmFacade,
            reasoningStreamManager: reasoningStreamManager
        )
        self.completionService = completionService ?? RevisionCompletionService()
        self.applicantProfileStore = applicantProfileStore
    }
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
    /// - Parameters:
    ///   - resume: The resume to revise
    ///   - modelId: The model to use for revisions
    func startFreshRevisionWorkflow(
        resume: Resume,
        modelId: String,
        workflow: RevisionWorkflowKind
    ) async throws {
        markWorkflowStarted(workflow)
        // Reset UI state
        resumeRevisions = []
        feedbackNodes = []
        currentRevisionNode = nil
        currentFeedbackNode = nil
        aiResubmit = false
        isProcessingRevisions = true
        do {
            // Create query for revision workflow
            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )
            // Start conversation with system prompt and user query
            let systemPrompt = query.genericSystemMessage.textContent
            let userPrompt = await query.wholeResumeQueryString()
            // Check if model supports reasoning for streaming
            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false
            // Debug logging to track reasoning interface triggering
            Logger.debug("🤖 [startFreshRevisionWorkflow] Model: \(modelId)")
            Logger.debug("🤖 [startFreshRevisionWorkflow] Model found: \(model != nil)")
            Logger.debug("🤖 [startFreshRevisionWorkflow] Model supportedParameters: \(model?.supportedParameters ?? [])")
            Logger.debug("🤖 [startFreshRevisionWorkflow] Supports reasoning: \(supportsReasoning)")
            // Defensive check: ensure reasoning modal is hidden for non-reasoning models
            if !supportsReasoning {
                reasoningStreamManager.hideAndClear()
            }
            let revisions: RevisionsContainer
            if supportsReasoning {
                // Use streaming with reasoning for supported models from the start
                Logger.info("🧠 Using streaming with reasoning for revision generation: \(modelId)")
                // Configure reasoning parameters for revision generation using user setting
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(
                    effort: userEffort,
                    includeReasoning: true
                )
                // Start streaming conversation with reasoning
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
                // Use non-streaming structured output for models without reasoning
                Logger.info("📝 Using non-streaming structured output for revision generation: \(modelId)")
                // Start conversation to maintain state for potential resubmission
                let (conversationId, _) = try await llm.startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId
                )
                self.currentConversationId = conversationId
                self.currentModelId = modelId
                // Get structured response from the conversation
                revisions = try await llm.continueConversationStructured(
                    userMessage: "Please provide the revision suggestions in the specified JSON format.",
                    modelId: modelId,
                    conversationId: conversationId,
                    as: RevisionsContainer.self,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
            }
            // Validate and process the revisions
            let validatedRevisions = validationService.validateRevisions(revisions.revArray, for: resume)
            // Set up the UI state for revision review
            await setupRevisionsForReview(validatedRevisions)
        } catch {
            isProcessingRevisions = false
            markWorkflowCompleted(reset: true)
            throw error
        }
    }
    /// Continue an existing conversation and generate revisions
    /// This is used when ClarifyingQuestionsViewModel hands off the conversation
    /// - Parameters:
    ///   - conversationId: The existing conversation ID from ClarifyingQuestionsViewModel
    ///   - resume: The resume being revised
    ///   - modelId: The model to continue with
    func continueConversationAndGenerateRevisions(
        conversationId: UUID,
        resume: Resume,
        modelId: String
    ) async throws {
        markWorkflowStarted(.clarifying)
        // Store the conversation context
        currentConversationId = conversationId
        currentModelId = modelId
        isProcessingRevisions = true
        do {
            // Create revision request with editable nodes only (context already established)
            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )
            let revisionRequestPrompt = await query.multiTurnRevisionPrompt()
            // Check if model supports reasoning for streaming
            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false
            // Debug logging to track reasoning interface triggering
            Logger.debug("🤖 [continueConversationAndGenerateRevisions] Model: \(modelId)")
            Logger.debug("🤖 [continueConversationAndGenerateRevisions] Model found: \(model != nil)")
            Logger.debug("🤖 [continueConversationAndGenerateRevisions] Supports reasoning: \(supportsReasoning)")
            // Only show reasoning modal for models that support reasoning
            if supportsReasoning {
                // Clear any previous reasoning content and reset state
                reasoningStreamManager.startReasoning(modelName: modelId)
            } else {
                // Defensive check: ensure reasoning modal is hidden for non-reasoning models
                reasoningStreamManager.hideAndClear()
            }
            let revisions: RevisionsContainer
            if supportsReasoning {
                // Use streaming with reasoning for supported models
                Logger.info("🧠 Using streaming with reasoning for revision continuation: \(modelId)")
                // Configure reasoning parameters using user setting
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
                // Use non-streaming for models without reasoning
                Logger.info("📝 Using non-streaming structured output for revision continuation: \(modelId)")
                revisions = try await llm.continueConversationStructured(
                    userMessage: revisionRequestPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    as: RevisionsContainer.self,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
            }
            // Process and validate revisions
            let validatedRevisions = validationService.validateRevisions(revisions.revArray, for: resume)
            // Set up the UI state for revision review
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
    /// - Parameter revisions: The validated revisions to review
    @MainActor
    private func setupRevisionsForReview(_ revisions: [ProposedRevisionNode]) async {
        Logger.debug("🔍 [ResumeReviseViewModel] setupRevisionsForReview called with \(revisions.count) revisions")
        Logger.debug("🔍 [ResumeReviseViewModel] Current instance address: \(String(describing: Unmanaged.passUnretained(self).toOpaque()))")
        // Set up revisions in the UI state
        resumeRevisions = revisions
        feedbackNodes = []
        feedbackIndex = 0
        // Set up the first revision for review
        if !revisions.isEmpty {
            currentRevisionNode = revisions[0]
            currentFeedbackNode = revisions[0].createFeedbackNode()
        }
        // Ensure reasoning modal is hidden before showing revision review
        Logger.debug("🔍 [ResumeReviseViewModel] Hiding reasoning modal")
        reasoningStreamManager.hideAndClear()
        // Show the revision review UI
        Logger.debug("🔍 [ResumeReviseViewModel] Setting showResumeRevisionSheet = true")
        showResumeRevisionSheet = true
        isProcessingRevisions = false
        markWorkflowCompleted(reset: false)
        Logger.debug("🔍 [ResumeReviseViewModel] After setting - showResumeRevisionSheet = \(showResumeRevisionSheet)")
    }
    // MARK: - Review Workflow Navigation (Moved from ReviewView)
    /// Save the current feedback and move to next node
    /// Clean interface that delegates to node logic
    func saveAndNext(response: PostReviewAction, resume: Resume) {
        guard let currentFeedbackNode = currentFeedbackNode else { return }
        // Let the feedback node handle its own action processing
        currentFeedbackNode.processAction(response)
        // Update UI state based on response
        switch response {
        case .acceptedWithChanges:
            isEditingResponse = false
        case .revise, .mandatedChangeNoComment:
            isCommenting = false
        default:
            break
        }
        let hasMore = nextNode(resume: resume)
        if hasMore {
            attemptAutomaticCompletionIfReady(resume: resume)
        }
    }
    /// Move to the next revision node in the workflow
    @discardableResult
    func nextNode(resume: Resume) -> Bool {
        // Add current feedback node to array
        if let currentFeedbackNode = currentFeedbackNode {
            if feedbackIndex < feedbackNodes.count {
                feedbackNodes[feedbackIndex] = currentFeedbackNode
            } else {
                feedbackNodes.append(currentFeedbackNode)
            }
            Logger.debug("Recorded feedback for node index \(feedbackIndex + 1) of \(resumeRevisions.count)")
        } else {
            Logger.warning("⚠️ Tried to advance without a currentFeedbackNode at index \(feedbackIndex)")
        }
        feedbackIndex += 1
        if feedbackIndex < resumeRevisions.count {
            Logger.debug("Moving to next node at index \(feedbackIndex)")
            currentRevisionNode = resumeRevisions[feedbackIndex]
            if feedbackIndex < feedbackNodes.count {
                currentFeedbackNode = feedbackNodes[feedbackIndex]
                restoreUIStateFromFeedbackNode(feedbackNodes[feedbackIndex])
            } else {
                currentFeedbackNode = currentRevisionNode?.createFeedbackNode()
                resetUIState()
            }
            return true
        } else {
            Logger.debug("Reached end of revisionArray. Processing completion...")
            completeReviewWorkflow(with: resume)
            return false
        }
    }
    /// Complete the review workflow - apply changes and handle resubmission
    func completeReviewWorkflow(with resume: Resume) {
        guard !isCompletingReview else {
            Logger.debug("⚠️ Ignoring re-entrant completeReviewWorkflow call")
            return
        }
        isCompletingReview = true
        defer { isCompletingReview = false }
        // Use completion service to determine next steps
        let result = completionService.completeReviewWorkflow(
            feedbackNodes: feedbackNodes,
            approvedFeedbackNodes: approvedFeedbackNodes,
            resume: resume,
            exportCoordinator: exportCoordinator
        )
        switch result {
        case .requiresResubmission(let nodesToResubmit, _):
            // Keep only nodes that need AI intervention for the next round
            feedbackNodes = nodesToResubmit
            // Start AI resubmission workflow
            startAIResubmission(with: resume)
        case .finished:
            Logger.debug("No nodes need resubmission. All changes applied, dismissing sheet...")
            Logger.debug("🔍 [completeReviewWorkflow] Setting showResumeRevisionSheet = false")
            Logger.debug("🔍 [completeReviewWorkflow] Current showResumeRevisionSheet value: \(showResumeRevisionSheet)")
            // Clear all state before dismissing
            approvedFeedbackNodes = []
            feedbackNodes = []
            resumeRevisions = []
            showResumeRevisionSheet = false
            Logger.debug("🔍 [completeReviewWorkflow] After setting - showResumeRevisionSheet = \(showResumeRevisionSheet)")
            markWorkflowCompleted(reset: true)
        }
    }
    /// Attempt to finish the workflow automatically once every revision has a response
    private func attemptAutomaticCompletionIfReady(resume: Resume) {
        guard !resumeRevisions.isEmpty else { return }
        guard !isCompletingReview else { return }
        // Check if all revisions have responses using completion service
        guard completionService.allRevisionsHaveResponses(
            feedbackNodes: feedbackNodes,
            resumeRevisions: resumeRevisions
        ) else { return }
        Logger.debug("✅ All revision nodes have responses. Completing workflow automatically.")
        completeReviewWorkflow(with: resume)
    }
    /// Start AI resubmission workflow
    private func startAIResubmission(with resume: Resume) {
        // Reset to original state before resubmitting to AI
        feedbackIndex = 0
        // Show loading UI
        aiResubmit = true
        workflowInProgress = true
        // Ensure PDF is fresh before resubmission
        Task {
            do {
                Logger.debug("Starting PDF re-rendering for AI resubmission...")
                try await exportCoordinator.ensureFreshRenderedText(for: resume)
                Logger.debug("PDF rendering complete for AI resubmission")
                // Actually perform the AI resubmission
                await performAIResubmission(with: resume)
            } catch {
                Logger.debug("Error rendering resume for AI resubmission: \(error)")
                await MainActor.run {
                    aiResubmit = false
                    workflowInProgress = false
                }
            }
        }
    }
    /// Perform the actual AI resubmission with feedback nodes requiring revision
    @MainActor
    private func performAIResubmission(with resume: Resume) async {
        guard let conversationId = currentConversationId else {
            Logger.error("No conversation ID available for AI resubmission")
            aiResubmit = false
            return
        }
        // Use the same model as the original conversation
        guard let modelId = currentModelId else {
            Logger.error("No model available for AI resubmission")
            aiResubmit = false
            return
        }
        // Check if model supports reasoning to determine UI behavior
        let model = openRouterService.findModel(id: modelId)
        let supportsReasoning = model?.supportsReasoning ?? false
        // For reasoning models, temporarily hide the review sheet
        if supportsReasoning {
            Logger.debug("🔍 Temporarily hiding review sheet for reasoning modal")
            showResumeRevisionSheet = false
        }
        do {
            // Create revision prompt from feedback nodes requiring resubmission
            let nodesToResubmit = feedbackNodes.filter { node in
                let aiActions: Set<PostReviewAction> = [.revise, .mandatedChange, .mandatedChangeNoComment, .rewriteNoComment]
                return aiActions.contains(node.actionRequested)
            }
            Logger.debug("🔄 Resubmitting \(nodesToResubmit.count) nodes to AI")
            // Use completion service to create revision prompt
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
            // Check if model supports reasoning for streaming during resubmission
            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false
            let revisions: RevisionsContainer
            if supportsReasoning {
                // Use streaming with reasoning for supported models
                Logger.info("🧠 Using streaming with reasoning for AI resubmission: \(modelId)")
                // Configure reasoning parameters using user setting
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
                // Use non-streaming for models without reasoning
                revisions = try await llm.continueConversationStructured(
                    userMessage: revisionPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    as: RevisionsContainer.self,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
            }
            // Validate and process the new revisions
            let validatedRevisions = validationService.validateRevisions(revisions.revArray, for: resume)
            // Get IDs of nodes that were resubmitted for updating
            let resubmittedNodeIds = Set(nodesToResubmit.map { $0.id })
            Logger.debug("🔍 Resubmitted \(nodesToResubmit.count) nodes, got back \(validatedRevisions.count) revisions")
            Logger.debug("🔍 Resubmitted node IDs: \(resubmittedNodeIds)")
            Logger.debug("🔍 Received revision IDs: \(validatedRevisions.map { $0.id })")
            // Filter validated revisions to only include ones that were actually requested for resubmission
            let requestedRevisions = validatedRevisions.filter { revision in
                resubmittedNodeIds.contains(revision.id)
            }
            if requestedRevisions.count != validatedRevisions.count {
                Logger.warning("⚠️ AI returned \(validatedRevisions.count) revisions but only \(requestedRevisions.count) were requested")
            }
            // For the second round, show ONLY the new revisions that need review
            // Keep approved feedback for final application, but don't show in UI
            let approvedFeedbackForLater = feedbackNodes.filter { feedback in
                !resubmittedNodeIds.contains(feedback.id)
            }
            // Replace arrays with only the new revisions requiring review
            resumeRevisions = requestedRevisions
            feedbackNodes = [] // Start fresh for new revisions
            // Reset to first revision (now only showing new ones)
            feedbackIndex = 0
            // Set up the first NEW revision for review
            if !resumeRevisions.isEmpty {
                currentRevisionNode = resumeRevisions[0]
                currentFeedbackNode = resumeRevisions[0].createFeedbackNode()
            }
            // Store approved feedback for final application
            // We'll need to merge this back when completing the workflow
            self.approvedFeedbackNodes = approvedFeedbackForLater
            // Clear loading state
            aiResubmit = false
            workflowInProgress = false
            // Show the review sheet again now that we have updated revisions
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
            // Ensure sheet is shown again so the user can recover
            showResumeRevisionSheet = true
        }
    }
    /// Initialize updateNodes for the review workflow
    func initializeUpdateNodes(for resume: Resume) {
        updateNodes = resume.getUpdatableNodes()
    }
    /// Navigate to previous revision node
    func navigateToPrevious() {
        guard feedbackIndex > 0 else {
            Logger.debug("Cannot navigate to previous: already at first revision")
            return
        }
        if let currentFeedbackNode = currentFeedbackNode {
            if feedbackIndex < feedbackNodes.count {
                feedbackNodes[feedbackIndex] = currentFeedbackNode
            } else {
                feedbackNodes.append(currentFeedbackNode)
            }
        }
        feedbackIndex -= 1
        guard ensureFeedbackIndexInBounds() else { return }
        currentRevisionNode = resumeRevisions[feedbackIndex]
        // Restore or create feedback node for this revision
        if feedbackIndex < feedbackNodes.count {
            currentFeedbackNode = feedbackNodes[feedbackIndex]
            // Restore UI state based on saved feedback
            restoreUIStateFromFeedbackNode(feedbackNodes[feedbackIndex])
        } else {
            currentFeedbackNode = currentRevisionNode?.createFeedbackNode()
            // Reset UI state for new feedback
            resetUIState()
        }
        Logger.debug("Navigated to previous revision: \(feedbackIndex + 1)/\(resumeRevisions.count)")
    }
    /// Navigate to next revision node
    func navigateToNext() {
        guard feedbackIndex < resumeRevisions.count - 1 else {
            Logger.debug("Cannot navigate to next: already at last revision")
            return
        }
        // Save current feedback node if it exists and isn't already saved
        if let currentFeedbackNode = currentFeedbackNode {
            if feedbackIndex < feedbackNodes.count {
                feedbackNodes[feedbackIndex] = currentFeedbackNode
            } else {
                feedbackNodes.append(currentFeedbackNode)
            }
        }
        feedbackIndex += 1
        // Validate bounds after adjusting index
        guard ensureFeedbackIndexInBounds() else { return }
        currentRevisionNode = resumeRevisions[feedbackIndex]
        // Restore or create feedback node for this revision
        if feedbackIndex < feedbackNodes.count {
            currentFeedbackNode = feedbackNodes[feedbackIndex]
            // Restore UI state based on saved feedback
            restoreUIStateFromFeedbackNode(feedbackNodes[feedbackIndex])
        } else {
            currentFeedbackNode = currentRevisionNode?.createFeedbackNode()
            // Reset UI state for new feedback
            resetUIState()
        }
        Logger.debug("Navigated to next revision: \(feedbackIndex + 1)/\(resumeRevisions.count)")
    }
    private func ensureFeedbackIndexInBounds() -> Bool {
        guard !resumeRevisions.isEmpty else {
            Logger.error("Navigation error: resumeRevisions collection is empty", category: .ui)
            feedbackIndex = 0
            currentRevisionNode = nil
            currentFeedbackNode = nil
            return false
        }
        guard feedbackIndex >= 0 && feedbackIndex < resumeRevisions.count else {
            Logger.error(
                "Navigation error: feedbackIndex \(feedbackIndex) out of bounds for resumeRevisions count \(resumeRevisions.count)",
                category: .ui
            )
            feedbackIndex = max(0, min(feedbackIndex, resumeRevisions.count - 1))
            return false
        }
        return true
    }
    /// Restore UI state from a saved feedback node
    private func restoreUIStateFromFeedbackNode(_ feedbackNode: FeedbackNode) {
        // Check if this node had commenting active based on action taken
        let commentingActions: Set<PostReviewAction> = [.revise, .mandatedChange]
        let moreCommentingActions: Set<PostReviewAction> = [.mandatedChangeNoComment]
        if commentingActions.contains(feedbackNode.actionRequested) && !feedbackNode.reviewerComments.isEmpty {
            isCommenting = true
            isMoreCommenting = false
        } else if moreCommentingActions.contains(feedbackNode.actionRequested) && !feedbackNode.reviewerComments.isEmpty {
            isCommenting = false
            isMoreCommenting = true
        } else {
            isCommenting = false
            isMoreCommenting = false
        }
        // Always reset editing state when navigating
        isEditingResponse = false
    }
    /// Check if a node was accepted (for button illumination)
    func isNodeAccepted(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        let acceptedActions: Set<PostReviewAction> = [.accepted, .acceptedWithChanges, .noChange]
        return acceptedActions.contains(feedbackNode.actionRequested)
    }
    /// Check if a node was rejected with comments (for thumbs down illumination)
    func isNodeRejectedWithComments(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .revise
    }
    /// Check if a node was rejected without comments (for trash button illumination)
    func isNodeRejectedWithoutComments(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .rewriteNoComment
    }
    /// Check if a node was restored to original (for restore button illumination)
    func isNodeRestored(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .restored
    }
    /// Check if a node was edited (for edit button illumination)
    func isNodeEdited(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .acceptedWithChanges
    }
    /// Reset UI state for new/fresh feedback nodes
    private func resetUIState() {
        isCommenting = false
        isMoreCommenting = false
        isEditingResponse = false
    }

    // MARK: - Two-Phase Hierarchical Review Workflow

    /// Start Phase 1: Category Structure Review
    /// Sends category names and keyword counts to LLM for structural proposals
    func startCategoryStructureReview(
        resume: Resume,
        modelId: String
    ) async throws {
        markWorkflowStarted(.customize)
        isProcessingRevisions = true
        isHierarchicalReviewActive = true
        currentRevisionPhase = .categoryStructure

        // Reset hierarchical review state
        categoryRevisions = []
        pendingCategoryIds = []
        approvedCategoryChanges = []
        approvedKeywordsChanges = [:]
        currentCategoryIndex = 0

        guard let rootNode = resume.rootNode else {
            Logger.error("❌ No root node found for hierarchical review")
            isProcessingRevisions = false
            markWorkflowCompleted(reset: true)
            throw NSError(domain: "ResumeReviseViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No root node found"])
        }

        do {
            // Export skill categories for Phase 1
            let categories = TreeNode.exportSkillCategories(from: rootNode)
            guard !categories.isEmpty else {
                Logger.warning("⚠️ No skill categories found for hierarchical review")
                isProcessingRevisions = false
                markWorkflowCompleted(reset: true)
                return
            }

            Logger.info("🚀 Starting Phase 1: Category Structure Review with \(categories.count) categories")

            // Create query for Phase 1
            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )

            // Generate Phase 1 prompt
            let systemPrompt = query.genericSystemMessage.textContent
            let userPrompt = await query.categoryStructurePrompt(categories: categories)

            // Check if model supports reasoning
            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false

            if !supportsReasoning {
                reasoningStreamManager.hideAndClear()
            }

            let container: CategoryRevisionsContainer

            if supportsReasoning {
                Logger.info("🧠 Using streaming with reasoning for Phase 1: \(modelId)")
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

                let result = try await streamingService.startConversationStreaming(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.categoryStructureSchema
                )

                self.currentConversationId = result.conversationId
                self.currentModelId = modelId

                // Parse the response as CategoryRevisionsContainer
                let jsonData = try JSONEncoder().encode(result.revisions)
                container = try JSONDecoder().decode(CategoryRevisionsContainer.self, from: jsonData)

            } else {
                Logger.info("📝 Using non-streaming for Phase 1: \(modelId)")

                let (conversationId, _) = try await llm.startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId
                )

                self.currentConversationId = conversationId
                self.currentModelId = modelId

                container = try await llm.continueConversationStructured(
                    userMessage: "Please provide your category structure proposals in the specified JSON format.",
                    modelId: modelId,
                    conversationId: conversationId,
                    as: CategoryRevisionsContainer.self,
                    jsonSchema: ResumeApiQuery.categoryStructureSchema
                )
            }

            // Store category revisions for review
            categoryRevisions = container.categories
            Logger.info("✅ Phase 1 received \(categoryRevisions.count) category proposals")

            // Hide reasoning modal and show review UI
            reasoningStreamManager.hideAndClear()
            showResumeRevisionSheet = true
            isProcessingRevisions = false
            markWorkflowCompleted(reset: false)

        } catch {
            Logger.error("❌ Phase 1 failed: \(error.localizedDescription)")
            isProcessingRevisions = false
            isHierarchicalReviewActive = false
            markWorkflowCompleted(reset: true)
            throw error
        }
    }

    /// Complete Phase 1 and transition to Phase 2
    /// Applies approved category structure changes and queues categories for keyword review
    func completeCategoryStructurePhase(resume: Resume, context: ModelContext) {
        // Store approved changes
        approvedCategoryChanges = categoryRevisions.filter { $0.userDecision == .accepted }

        // Apply category structure changes immediately
        guard let rootNode = resume.rootNode else { return }
        TreeNode.applyCategoryStructureChanges(approvedCategoryChanges, to: rootNode, context: context)

        // Queue remaining categories for Phase 2 keyword review
        // Only categories that weren't removed need keyword review
        let removedCategoryIds = Set(approvedCategoryChanges.filter { $0.action == .remove }.map { $0.id })
        pendingCategoryIds = categoryRevisions
            .filter { $0.action != .add && !removedCategoryIds.contains($0.id) }
            .map { $0.id }

        // Include new categories that need keywords
        let newCategories = approvedCategoryChanges.filter { $0.action == .add }
        pendingCategoryIds.append(contentsOf: newCategories.map { $0.id })

        Logger.info("🔄 Phase 1 complete. \(pendingCategoryIds.count) categories queued for Phase 2")

        // Transition to Phase 2
        currentRevisionPhase = .categoryDetails
        currentCategoryIndex = 0

        // Start Phase 2 for first category if any
        if !pendingCategoryIds.isEmpty {
            Task {
                await startKeywordsReviewForCurrentCategory(resume: resume)
            }
        } else {
            // No categories need keyword review - finish workflow
            finishHierarchicalReview(resume: resume)
        }
    }

    /// Start Phase 2: Keywords review for the current category
    func startKeywordsReviewForCurrentCategory(resume: Resume) async {
        guard currentCategoryIndex < pendingCategoryIds.count else {
            Logger.debug("✅ All categories reviewed in Phase 2")
            finishHierarchicalReview(resume: resume)
            return
        }

        let categoryId = pendingCategoryIds[currentCategoryIndex]
        isProcessingRevisions = true

        guard let rootNode = resume.rootNode else {
            Logger.error("❌ No root node for Phase 2")
            isProcessingRevisions = false
            return
        }

        guard let categoryData = TreeNode.exportCategoryKeywords(categoryId: categoryId, from: rootNode) else {
            Logger.warning("⚠️ Category \(categoryId) not found, skipping")
            currentCategoryIndex += 1
            await startKeywordsReviewForCurrentCategory(resume: resume)
            return
        }

        Logger.info("🚀 Starting Phase 2 for '\(categoryData.categoryName)' (\(categoryData.keywords.count) keywords)")

        guard let conversationId = currentConversationId, let modelId = currentModelId else {
            Logger.error("❌ No conversation context for Phase 2")
            isProcessingRevisions = false
            return
        }

        do {
            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )

            let userPrompt = await query.categoryKeywordsPrompt(
                categoryId: categoryId,
                categoryName: categoryData.categoryName,
                keywords: categoryData.keywords
            )

            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false

            let keywordsRevision: KeywordsRevisionContainer

            if supportsReasoning {
                Logger.info("🧠 Using streaming for Phase 2 keywords")
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

                let result = try await streamingService.continueConversationStreaming(
                    userMessage: userPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.keywordsArraySchema
                )

                // Parse response
                let jsonData = try JSONEncoder().encode(result)
                keywordsRevision = try JSONDecoder().decode(KeywordsRevisionContainer.self, from: jsonData)

            } else {
                keywordsRevision = try await llm.continueConversationStructured(
                    userMessage: userPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    as: KeywordsRevisionContainer.self,
                    jsonSchema: ResumeApiQuery.keywordsArraySchema
                )
            }

            currentKeywordsRevision = keywordsRevision
            Logger.info("✅ Received keywords revision: \(keywordsRevision.oldKeywords.count) → \(keywordsRevision.newKeywords.count)")

            reasoningStreamManager.hideAndClear()
            isProcessingRevisions = false

        } catch {
            Logger.error("❌ Phase 2 failed for category \(categoryId): \(error.localizedDescription)")
            isProcessingRevisions = false
            // Skip this category and continue with next
            currentCategoryIndex += 1
            await startKeywordsReviewForCurrentCategory(resume: resume)
        }
    }

    /// Accept keywords revision for current category and move to next
    func acceptCurrentKeywordsAndMoveNext(resume: Resume, context: ModelContext) {
        guard let keywordsRevision = currentKeywordsRevision else { return }
        guard let rootNode = resume.rootNode else { return }

        // Store approved change
        approvedKeywordsChanges[keywordsRevision.categoryId] = keywordsRevision

        // Apply the keywords change
        TreeNode.applyKeywordsChanges(
            categoryId: keywordsRevision.categoryId,
            newKeywords: keywordsRevision.newKeywords,
            to: rootNode,
            context: context
        )

        Logger.info("✅ Applied keywords for '\(keywordsRevision.categoryName)'")

        // Move to next category
        currentCategoryIndex += 1
        currentKeywordsRevision = nil

        Task {
            await startKeywordsReviewForCurrentCategory(resume: resume)
        }
    }

    /// Reject keywords revision for current category and move to next
    func rejectCurrentKeywordsAndMoveNext(resume: Resume) {
        Logger.info("⏭️ Skipped keywords revision for current category")

        currentCategoryIndex += 1
        currentKeywordsRevision = nil

        Task {
            await startKeywordsReviewForCurrentCategory(resume: resume)
        }
    }

    /// Finish the hierarchical review workflow
    func finishHierarchicalReview(resume: Resume) {
        Logger.info("🏁 Hierarchical review complete")
        Logger.info("  - Category changes: \(approvedCategoryChanges.count)")
        Logger.info("  - Keywords changes: \(approvedKeywordsChanges.count)")

        // Trigger PDF refresh
        exportCoordinator.debounceExport(resume: resume)

        // Clear state and dismiss
        clearHierarchicalReviewState()
        showResumeRevisionSheet = false
        markWorkflowCompleted(reset: true)
    }

    /// Check if there are unapplied approved changes (for cancel confirmation)
    func hasUnappliedApprovedChanges() -> Bool {
        !approvedCategoryChanges.isEmpty || !approvedKeywordsChanges.isEmpty
    }

    /// Apply all approved changes and close (for cancel with partial approval)
    func applyApprovedChangesAndClose(resume: Resume, context: ModelContext) {
        guard let rootNode = resume.rootNode else { return }

        // Apply any remaining category changes
        TreeNode.applyCategoryStructureChanges(approvedCategoryChanges, to: rootNode, context: context)

        // Apply any remaining keywords changes
        for (categoryId, keywordsRevision) in approvedKeywordsChanges {
            TreeNode.applyKeywordsChanges(
                categoryId: categoryId,
                newKeywords: keywordsRevision.newKeywords,
                to: rootNode,
                context: context
            )
        }

        // Trigger PDF refresh
        exportCoordinator.debounceExport(resume: resume)

        clearHierarchicalReviewState()
        showResumeRevisionSheet = false
        markWorkflowCompleted(reset: true)
    }

    /// Discard all changes and close
    func discardAllAndClose() {
        clearHierarchicalReviewState()
        showResumeRevisionSheet = false
        markWorkflowCompleted(reset: true)
    }

    /// Clear all hierarchical review state
    private func clearHierarchicalReviewState() {
        isHierarchicalReviewActive = false
        currentRevisionPhase = .categoryStructure
        categoryRevisions = []
        pendingCategoryIds = []
        currentCategoryIndex = 0
        currentKeywordsRevision = nil
        approvedCategoryChanges = []
        approvedKeywordsChanges = [:]
    }
}
// MARK: - Supporting Types
// MARK: - Note: Using existing types from AITypes.swift and ResumeUpdateNode.swift
// - RevisionsContainer (with revArray property)
// - ClarifyingQuestionsRequest 
// - ClarifyingQuestion
// - QuestionAnswer
