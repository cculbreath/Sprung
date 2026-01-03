//
//  RevisionWorkflowOrchestrator.swift
//  Sprung
//
//  Service responsible for orchestrating revision workflow execution.
//  Handles the core workflow logic for generating and resubmitting revisions.
//

import Foundation
import SwiftUI
import SwiftData

/// Protocol for receiving workflow orchestration callbacks
@MainActor
protocol RevisionWorkflowOrchestratorDelegate: AnyObject {
    func setupRevisionsForReview(_ revisions: [ProposedRevisionNode]) async
    func handleResubmissionResults(validatedRevisions: [ProposedRevisionNode], resubmittedNodeIds: Set<String>)
    var showResumeRevisionSheet: Bool { get set }
}

/// Service responsible for orchestrating revision workflow execution.
/// Coordinates LLM calls, tool execution, and revision generation.
@MainActor
@Observable
class RevisionWorkflowOrchestrator {
    // MARK: - Dependencies
    private let llm: LLMFacade
    private let openRouterService: OpenRouterService
    private let reasoningStreamManager: ReasoningStreamManager
    private let exportCoordinator: ResumeExportCoordinator
    private let validationService: RevisionValidationService
    private let streamingService: RevisionStreamingService
    private let completionService: RevisionCompletionService
    private let applicantProfileStore: ApplicantProfileStore
    private let resRefStore: ResRefStore
    private let toolRunner: ToolConversationRunner
    private let phaseReviewManager: PhaseReviewManager
    private let guidanceStore: InferenceGuidanceStore?

    // MARK: - Delegate
    weak var delegate: RevisionWorkflowOrchestratorDelegate?

    // MARK: - State
    let workflowState: RevisionWorkflowState

    // MARK: - Initialization

    init(
        llm: LLMFacade,
        openRouterService: OpenRouterService,
        reasoningStreamManager: ReasoningStreamManager,
        exportCoordinator: ResumeExportCoordinator,
        validationService: RevisionValidationService,
        streamingService: RevisionStreamingService,
        completionService: RevisionCompletionService,
        applicantProfileStore: ApplicantProfileStore,
        resRefStore: ResRefStore,
        toolRunner: ToolConversationRunner,
        phaseReviewManager: PhaseReviewManager,
        guidanceStore: InferenceGuidanceStore? = nil,
        workflowState: RevisionWorkflowState
    ) {
        self.llm = llm
        self.openRouterService = openRouterService
        self.reasoningStreamManager = reasoningStreamManager
        self.exportCoordinator = exportCoordinator
        self.validationService = validationService
        self.streamingService = streamingService
        self.completionService = completionService
        self.applicantProfileStore = applicantProfileStore
        self.resRefStore = resRefStore
        self.toolRunner = toolRunner
        self.phaseReviewManager = phaseReviewManager
        self.guidanceStore = guidanceStore
        self.workflowState = workflowState
    }

    // MARK: - Workflow Execution

    /// Start a fresh revision workflow (without clarifying questions)
    func startFreshRevisionWorkflow(
        resume: Resume,
        modelId: String,
        workflow: RevisionWorkflowState.WorkflowKind
    ) async throws {
        // Use two-round review workflow:
        // Round 1: Phase 1 items from configured sections (e.g., skill category names)
        // Round 2: Everything else (phase 2+ items + all other AI-selected nodes)
        let (phase1Nodes, phase2Nodes) = phaseReviewManager.buildReviewRounds(for: resume)

        if !phase1Nodes.isEmpty || !phase2Nodes.isEmpty {
            Logger.info("🎯 Starting two-round review workflow")
            Logger.info("📋 Round 1: \(phase1Nodes.count) nodes, Round 2: \(phase2Nodes.count) nodes")
            try await phaseReviewManager.startTwoRoundReview(resume: resume, modelId: modelId)
            return
        }

        workflowState.markWorkflowStarted(workflow)
        workflowState.setProcessingRevisions(true)

        do {
            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                allResRefs: resRefStore.resRefs,
                guidanceStore: guidanceStore,
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
                workflowState.currentModelId = modelId

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

                workflowState.setConversationContext(conversationId: result.conversationId, modelId: modelId)
                revisions = result.revisions

            } else {
                Logger.info("📝 Using non-streaming structured output for revision generation: \(modelId)")

                let (conversationId, _) = try await llm.startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId
                )

                workflowState.setConversationContext(conversationId: conversationId, modelId: modelId)

                revisions = try await llm.continueConversationStructured(
                    userMessage: "Please provide the revision suggestions in the specified JSON format.",
                    modelId: modelId,
                    conversationId: conversationId,
                    as: RevisionsContainer.self,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
            }

            let validatedRevisions = validationService.validateRevisions(revisions.revArray, for: resume)
            reasoningStreamManager.hideAndClear()
            await delegate?.setupRevisionsForReview(validatedRevisions)

        } catch {
            workflowState.setProcessingRevisions(false)
            workflowState.markWorkflowCompleted(reset: true)
            throw error
        }
    }

    /// Continue an existing conversation and generate revisions
    func continueConversationAndGenerateRevisions(
        conversationId: UUID,
        resume: Resume,
        modelId: String
    ) async throws {
        workflowState.markWorkflowStarted(.clarifying)
        workflowState.setConversationContext(conversationId: conversationId, modelId: modelId)
        workflowState.setProcessingRevisions(true)

        do {
            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                allResRefs: resRefStore.resRefs,
                guidanceStore: guidanceStore,
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
            reasoningStreamManager.hideAndClear()
            await delegate?.setupRevisionsForReview(validatedRevisions)
            Logger.debug("✅ Conversation handoff complete: \(validatedRevisions.count) revisions ready for review")

        } catch {
            Logger.error("Error continuing conversation for revisions: \(error.localizedDescription)")
            workflowState.setProcessingRevisions(false)
            workflowState.markWorkflowCompleted(reset: true)
            throw error
        }
    }

    /// Perform AI resubmission with feedback nodes requiring revision
    func performAIResubmission(
        with resume: Resume,
        feedbackNodes: [FeedbackNode],
        exportCoordinator: ResumeExportCoordinator
    ) async {
        guard let conversationId = workflowState.currentConversationId else {
            Logger.error("No conversation ID available for AI resubmission")
            workflowState.aiResubmit = false
            return
        }

        guard let modelId = workflowState.currentModelId else {
            Logger.error("No model available for AI resubmission")
            workflowState.aiResubmit = false
            return
        }

        let model = openRouterService.findModel(id: modelId)
        let supportsReasoning = model?.supportsReasoning ?? false

        if supportsReasoning {
            Logger.debug("🔍 Temporarily hiding review sheet for reasoning modal")
            delegate?.showResumeRevisionSheet = false
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
                workflowState.aiResubmit = false
                workflowState.workflowInProgress = false
                delegate?.showResumeRevisionSheet = true
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

            delegate?.handleResubmissionResults(
                validatedRevisions: validatedRevisions,
                resubmittedNodeIds: resubmittedNodeIds
            )

            workflowState.aiResubmit = false
            workflowState.workflowInProgress = false

            if supportsReasoning {
                Logger.debug("🔍 Showing review sheet again after reasoning modal")
            } else {
                Logger.debug("🔍 Reopening review sheet after resubmission (non-reasoning model)")
            }
            delegate?.showResumeRevisionSheet = true

            Logger.debug("✅ AI resubmission complete: \(validatedRevisions.count) new revisions ready for review")

        } catch {
            Logger.error("Error in AI resubmission: \(error.localizedDescription)")
            workflowState.aiResubmit = false
            workflowState.workflowInProgress = false
            delegate?.showResumeRevisionSheet = true
        }
    }
}
