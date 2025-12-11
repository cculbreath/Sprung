//
//  ResumeReviseViewModel.swift
//  Sprung
//
//
import Foundation
import SwiftUI
import SwiftData
import SwiftOpenAI
import SwiftyJSON
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

    // MARK: - Generic Multi-Phase Review State

    /// State for tracking multi-phase review workflow (manifest-driven)
    var phaseReviewState = PhaseReviewState()

    /// Computed property for view compatibility
    var isHierarchicalReviewActive: Bool {
        phaseReviewState.isActive
    }
    // MARK: - Business Logic State
    private var currentConversationId: UUID?
    var currentModelId: String? // Make currentModelId accessible to views
    private(set) var isProcessingRevisions: Bool = false
    private var isCompletingReview: Bool = false

    // MARK: - Tool Calling State
    private let toolRegistry: ResumeToolRegistry
    var showSkillExperiencePicker: Bool = false
    var pendingSkillQueries: [SkillQuery] = []
    private var skillUIResponseContinuation: CheckedContinuation<ResumeToolUIResponse, Never>?
    init(
        llmFacade: LLMFacade,
        openRouterService: OpenRouterService,
        reasoningStreamManager: ReasoningStreamManager,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfileStore: ApplicantProfileStore,
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
        self.streamingService = streamingService ?? RevisionStreamingService(
            llm: llmFacade,
            reasoningStreamManager: reasoningStreamManager
        )
        self.completionService = completionService ?? RevisionCompletionService()
        self.applicantProfileStore = applicantProfileStore
        self.toolRegistry = toolRegistry ?? ResumeToolRegistry()
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
        // Check if any sections have multi-phase review configured
        let sectionsWithPhases = sectionsWithActiveReviewPhases(for: resume)
        if let firstSection = sectionsWithPhases.first {
            Logger.info("🎯 Using multi-phase review for '\(firstSection.section)' with \(firstSection.phases.count) phases")
            try await startPhaseReview(
                resume: resume,
                section: firstSection.section,
                phases: firstSection.phases,
                modelId: modelId
            )
            return
        }

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

            // Check if tools should be used
            let useTools = shouldUseTools(modelId: modelId)
            Logger.debug("🤖 [startFreshRevisionWorkflow] Use tools: \(useTools)")

            // Defensive check: ensure reasoning modal is hidden for non-reasoning models
            if !supportsReasoning {
                reasoningStreamManager.hideAndClear()
            }
            let revisions: RevisionsContainer

            // Tool-enabled workflow (takes precedence when available)
            if useTools && !supportsReasoning {
                // Use tool-enabled conversation for models that support tools but not reasoning
                // (Reasoning models use a different path that doesn't support tools yet)
                Logger.info("🔧 [Tools] Using tool-enabled conversation for revision generation: \(modelId)")
                self.currentModelId = modelId

                // Get the job app for context (not directly available from Resume, so nil for now)
                let jobApp: JobApp? = nil

                // Enhance system prompt with tool instructions
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

                // Run tool-enabled conversation
                let finalResponse = try await runToolEnabledConversation(
                    systemPrompt: toolSystemPrompt,
                    userPrompt: userPrompt + "\n\nPlease provide the revision suggestions in the specified JSON format.",
                    modelId: modelId,
                    resume: resume,
                    jobApp: jobApp
                )

                // Parse the response as revisions
                revisions = try parseRevisionsFromResponse(finalResponse)

            } else if supportsReasoning {
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

    // MARK: - Tool Calling Support

    /// Check if tool calling should be used for this model
    private func shouldUseTools(modelId: String) -> Bool {
        let toolsEnabled = UserDefaults.standard.bool(forKey: "enableResumeCustomizationTools")
        guard toolsEnabled else {
            Logger.debug("🔧 [Tools] Feature flag disabled")
            return false
        }

        let model = openRouterService.findModel(id: modelId)
        let supportsTools = model?.supportsTools ?? false
        Logger.debug("🔧 [Tools] Model \(modelId) supportsTools: \(supportsTools)")
        return supportsTools
    }

    /// Run a tool-enabled conversation with the LLM.
    /// Executes a loop: LLM response → tool calls → tool execution → tool results → repeat until no more tool calls.
    /// - Returns: The final text response from the LLM after all tool calls are resolved.
    private func runToolEnabledConversation(
        systemPrompt: String,
        userPrompt: String,
        modelId: String,
        resume: Resume,
        jobApp: JobApp?
    ) async throws -> String {
        Logger.info("🔧 [Tools] Starting tool-enabled conversation with \(toolRegistry.toolNames.count) tools")

        // Build initial messages
        var messages: [SwiftOpenAI.ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text(systemPrompt)),
            .init(role: .user, content: .text(userPrompt))
        ]

        // Build tools
        let tools = toolRegistry.buildChatTools()

        // Tool execution loop
        var maxIterations = 10
        while maxIterations > 0 {
            maxIterations -= 1

            let response = try await llm.executeWithTools(
                messages: messages,
                tools: tools,
                toolChoice: .auto,
                modelId: modelId,
                temperature: 0.7
            )

            guard let choice = response.choices?.first,
                  let message = choice.message else {
                throw LLMError.clientError("No response from model")
            }

            // Check for tool calls
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                Logger.info("🔧 [Tools] Model requested \(toolCalls.count) tool call(s)")

                // Add assistant message with tool calls to history
                let assistantContent: ChatCompletionParameters.Message.ContentType = message.content.map { .text($0) } ?? .text("")
                messages.append(ChatCompletionParameters.Message(
                    role: .assistant,
                    content: assistantContent,
                    toolCalls: toolCalls
                ))

                // Execute each tool and collect results
                for toolCall in toolCalls {
                    let toolCallId = toolCall.id ?? UUID().uuidString
                    let toolName = toolCall.function.name ?? "unknown"
                    let toolArguments = toolCall.function.arguments

                    Logger.debug("🔧 [Tools] Executing tool: \(toolName)")

                    let context = ResumeToolContext(
                        resume: resume,
                        jobApp: jobApp,
                        presentUI: { [weak self] request in
                            await self?.handleToolUIRequest(request) ?? .cancelled
                        }
                    )

                    let result = try await toolRegistry.executeTool(
                        name: toolName,
                        arguments: toolArguments,
                        context: context
                    )

                    // Handle the result
                    let resultString: String
                    switch result {
                    case .immediate(let json):
                        resultString = json.rawString() ?? "{}"

                    case .pendingUserAction(let uiRequest):
                        // Present UI and wait for user response
                        let uiResponse = await handleToolUIRequest(uiRequest)
                        switch uiResponse {
                        case .skillExperienceResults(let results):
                            resultString = QueryUserExperienceLevelTool.formatResults(results)
                        case .cancelled:
                            resultString = QueryUserExperienceLevelTool.formatCancellation()
                        }

                    case .error(let errorMessage):
                        resultString = """
                        {"error": "\(errorMessage)"}
                        """
                    }

                    // Add tool result message
                    messages.append(ChatCompletionParameters.Message(
                        role: .tool,
                        content: .text(resultString),
                        toolCallID: toolCallId
                    ))
                }
            } else {
                // No tool calls - return the final response
                let finalContent = message.content ?? ""
                Logger.info("🔧 [Tools] Conversation complete, returning final response")
                return finalContent
            }
        }

        throw LLMError.clientError("Tool execution exceeded maximum iterations")
    }

    /// Handle UI request from a tool by presenting the appropriate UI and waiting for response
    @MainActor
    private func handleToolUIRequest(_ request: ResumeToolUIRequest) async -> ResumeToolUIResponse {
        switch request {
        case .skillExperiencePicker(let skills):
            return await presentSkillExperiencePicker(skills)
        }
    }

    /// Present the skill experience picker and wait for user response
    @MainActor
    private func presentSkillExperiencePicker(_ skills: [SkillQuery]) async -> ResumeToolUIResponse {
        return await withCheckedContinuation { continuation in
            self.skillUIResponseContinuation = continuation
            self.pendingSkillQueries = skills
            self.showSkillExperiencePicker = true
            // The continuation will be resumed by submitSkillExperienceResults or cancelSkillExperienceQuery
        }
    }

    /// Submit skill experience results from the UI
    func submitSkillExperienceResults(_ results: [SkillExperienceResult]) {
        showSkillExperiencePicker = false
        pendingSkillQueries = []
        skillUIResponseContinuation?.resume(returning: .skillExperienceResults(results))
        skillUIResponseContinuation = nil
    }

    /// Cancel the skill experience query
    func cancelSkillExperienceQuery() {
        showSkillExperiencePicker = false
        pendingSkillQueries = []
        skillUIResponseContinuation?.resume(returning: .cancelled)
        skillUIResponseContinuation = nil
    }

    /// Parse revisions from a raw LLM response string
    private func parseRevisionsFromResponse(_ response: String) throws -> RevisionsContainer {
        // Try to extract JSON from the response
        // The response may contain markdown code blocks or just raw JSON
        let jsonString: String
        if let jsonStart = response.range(of: "["),
           let jsonEnd = response.range(of: "]", options: .backwards) {
            // Extract the JSON array portion
            jsonString = String(response[jsonStart.lowerBound...jsonEnd.upperBound])
        } else if let jsonStart = response.range(of: "{"),
                  let jsonEnd = response.range(of: "}", options: .backwards) {
            // Try object format (the container might be an object with revArray)
            jsonString = String(response[jsonStart.lowerBound...jsonEnd.upperBound])
        } else {
            jsonString = response
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw LLMError.clientError("Failed to convert response to data")
        }

        // Try to decode as RevisionsContainer first
        do {
            return try JSONDecoder().decode(RevisionsContainer.self, from: data)
        } catch {
            // Try to decode as an array of revisions directly
            do {
                let revisions = try JSONDecoder().decode([ProposedRevisionNode].self, from: data)
                return RevisionsContainer(revArray: revisions)
            } catch {
                Logger.error("Failed to parse revisions from response: \(error.localizedDescription)")
                Logger.debug("Response was: \(response.prefix(500))...")
                throw LLMError.clientError("Failed to parse revision response: \(error.localizedDescription)")
            }
        }
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

    // MARK: - Generic Manifest-Driven Multi-Phase Review Workflow

    /// Find sections with review phases defined that have nodes selected for AI revision.
    /// Returns array of (section, phases) tuples for sections that should use phased review.
    func sectionsWithActiveReviewPhases(for resume: Resume) -> [(section: String, phases: [TemplateManifest.ReviewPhaseConfig])] {
        // Diagnostic logging
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] Starting check...")
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] template: \(resume.template != nil ? "exists" : "nil")")
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] manifestData: \(resume.template?.manifestData != nil ? "\(resume.template!.manifestData!.count) bytes" : "nil")")
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] rootNode: \(resume.rootNode != nil ? "exists" : "nil")")

        // Use TemplateManifestLoader to properly merge base manifest with overrides
        // (resume.template?.manifest fails because manifestData only contains overrides, not full manifest)
        guard let template = resume.template,
              let rootNode = resume.rootNode else {
            Logger.warning("⚠️ [sectionsWithActiveReviewPhases] Bailing - template or rootNode nil")
            return []
        }

        guard let manifest = TemplateManifestLoader.manifest(for: template) else {
            Logger.warning("⚠️ [sectionsWithActiveReviewPhases] Failed to load manifest via TemplateManifestLoader")
            return []
        }
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] manifest loaded via TemplateManifestLoader")

        Logger.debug("🔍 [sectionsWithActiveReviewPhases] reviewPhases: \(manifest.reviewPhases != nil ? "\(manifest.reviewPhases!.keys.joined(separator: ", "))" : "nil")")

        var result: [(section: String, phases: [TemplateManifest.ReviewPhaseConfig])] = []

        // Check all sections that have reviewPhases defined
        if let reviewPhases = manifest.reviewPhases {
            for (section, phases) in reviewPhases {
                Logger.debug("🔍 [sectionsWithActiveReviewPhases] Checking section '\(section)' with \(phases.count) phases")
                // Find the section node and check if it has AI-selected nodes
                if let sectionNode = rootNode.children?.first(where: { $0.name.lowercased() == section.lowercased() }) {
                    let hasSelected = sectionNode.status == .aiToReplace || sectionNode.aiStatusChildren > 0
                    Logger.debug("🔍 [sectionsWithActiveReviewPhases] Section '\(section)' found - status=\(sectionNode.status), aiStatusChildren=\(sectionNode.aiStatusChildren), hasSelected=\(hasSelected)")
                    if hasSelected && !phases.isEmpty {
                        let sortedPhases = phases.sorted { $0.phase < $1.phase }
                        result.append((section: section, phases: sortedPhases))
                        Logger.info("📋 Section '\(section)' has \(sortedPhases.count) review phases configured - USING PHASED REVIEW")
                    }
                } else {
                    Logger.debug("🔍 [sectionsWithActiveReviewPhases] Section '\(section)' NOT found in rootNode.children")
                }
            }
        } else {
            Logger.debug("🔍 [sectionsWithActiveReviewPhases] manifest.reviewPhases is nil")
        }

        Logger.debug("🔍 [sectionsWithActiveReviewPhases] Returning \(result.count) sections with active phases")
        return result
    }

    /// Start the multi-phase review workflow for a section.
    /// Reads phases from manifest and processes them in order.
    func startPhaseReview(
        resume: Resume,
        section: String,
        phases: [TemplateManifest.ReviewPhaseConfig],
        modelId: String
    ) async throws {
        markWorkflowStarted(.customize)
        isProcessingRevisions = true

        // Initialize phase review state
        phaseReviewState.reset()
        phaseReviewState.isActive = true
        phaseReviewState.currentSection = section
        phaseReviewState.phases = phases
        phaseReviewState.currentPhaseIndex = 0

        guard let rootNode = resume.rootNode else {
            Logger.error("❌ No root node found for phase review")
            isProcessingRevisions = false
            phaseReviewState.reset()
            markWorkflowCompleted(reset: true)
            throw NSError(domain: "ResumeReviseViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No root node found"])
        }

        guard let currentPhase = phaseReviewState.currentPhase else {
            Logger.error("❌ No phases configured")
            isProcessingRevisions = false
            phaseReviewState.reset()
            markWorkflowCompleted(reset: true)
            return
        }

        do {
            // Export nodes matching the phase's field path
            let exportedNodes = TreeNode.exportNodesMatchingPath(currentPhase.field, from: rootNode)
            guard !exportedNodes.isEmpty else {
                Logger.warning("⚠️ No nodes found matching path '\(currentPhase.field)'")
                // Try next phase or finish
                await advanceToNextPhase(resume: resume)
                return
            }

            Logger.info("🚀 Starting Phase \(currentPhase.phase) for '\(section)' - \(exportedNodes.count) nodes matching '\(currentPhase.field)'")

            // Create query
            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )

            // Generate prompt
            let systemPrompt = query.genericSystemMessage.textContent
            let userPrompt = await query.phaseReviewPrompt(
                section: section,
                phaseNumber: currentPhase.phase,
                fieldPath: currentPhase.field,
                nodes: exportedNodes,
                isBundled: currentPhase.bundle
            )

            // Check if model supports reasoning
            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false

            if !supportsReasoning {
                reasoningStreamManager.hideAndClear()
            }

            let reviewContainer: PhaseReviewContainer

            if supportsReasoning {
                Logger.info("🧠 Using streaming with reasoning for phase review: \(modelId)")
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

                let result = try await streamingService.startConversationStreaming(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema
                )

                self.currentConversationId = result.conversationId
                self.currentModelId = modelId

                // Parse the response
                let jsonData = try JSONEncoder().encode(result.revisions)
                reviewContainer = try JSONDecoder().decode(PhaseReviewContainer.self, from: jsonData)

            } else {
                Logger.info("📝 Using non-streaming for phase review: \(modelId)")

                let (conversationId, _) = try await llm.startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId
                )

                self.currentConversationId = conversationId
                self.currentModelId = modelId

                reviewContainer = try await llm.continueConversationStructured(
                    userMessage: "Please provide your review proposals in the specified JSON format.",
                    modelId: modelId,
                    conversationId: conversationId,
                    as: PhaseReviewContainer.self,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema
                )
            }

            // Store review for user interaction
            phaseReviewState.currentReview = reviewContainer
            Logger.info("✅ Phase \(currentPhase.phase) received \(reviewContainer.items.count) review proposals")

            // If not bundled, set up item-by-item review
            if !currentPhase.bundle {
                phaseReviewState.pendingItemIds = reviewContainer.items.map { $0.id }
                phaseReviewState.currentItemIndex = 0
            }

            // Hide reasoning modal and show review UI
            reasoningStreamManager.hideAndClear()
            showResumeRevisionSheet = true
            isProcessingRevisions = false
            markWorkflowCompleted(reset: false)

        } catch {
            Logger.error("❌ Phase review failed: \(error.localizedDescription)")
            isProcessingRevisions = false
            phaseReviewState.reset()
            markWorkflowCompleted(reset: true)
            throw error
        }
    }

    /// Complete the current phase and move to the next one.
    func completeCurrentPhase(resume: Resume, context: ModelContext) {
        guard let currentReview = phaseReviewState.currentReview,
              let rootNode = resume.rootNode else { return }

        // Apply approved changes
        TreeNode.applyPhaseReviewChanges(currentReview, to: rootNode, context: context)

        // Store in approved reviews
        phaseReviewState.approvedReviews.append(currentReview)

        Logger.info("🔄 Phase \(phaseReviewState.currentPhaseIndex + 1) complete")

        // Move to next phase
        Task {
            await advanceToNextPhase(resume: resume)
        }
    }

    /// Advance to the next phase or finish the workflow.
    private func advanceToNextPhase(resume: Resume) async {
        phaseReviewState.currentPhaseIndex += 1
        phaseReviewState.currentReview = nil
        phaseReviewState.pendingItemIds = []
        phaseReviewState.currentItemIndex = 0

        if phaseReviewState.isLastPhase || phaseReviewState.currentPhaseIndex >= phaseReviewState.phases.count {
            finishPhaseReview(resume: resume)
            return
        }

        // Start next phase
        guard let nextPhase = phaseReviewState.currentPhase,
              let rootNode = resume.rootNode,
              let modelId = currentModelId else {
            finishPhaseReview(resume: resume)
            return
        }

        isProcessingRevisions = true

        do {
            let exportedNodes = TreeNode.exportNodesMatchingPath(nextPhase.field, from: rootNode)
            guard !exportedNodes.isEmpty else {
                Logger.warning("⚠️ No nodes found for phase \(nextPhase.phase)")
                await advanceToNextPhase(resume: resume)
                return
            }

            Logger.info("🚀 Starting Phase \(nextPhase.phase) - \(exportedNodes.count) nodes")

            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )

            let userPrompt = await query.phaseReviewPrompt(
                section: phaseReviewState.currentSection,
                phaseNumber: nextPhase.phase,
                fieldPath: nextPhase.field,
                nodes: exportedNodes,
                isBundled: nextPhase.bundle
            )

            guard let conversationId = currentConversationId else {
                Logger.error("❌ No conversation context for next phase")
                finishPhaseReview(resume: resume)
                return
            }

            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false

            let reviewContainer: PhaseReviewContainer

            if supportsReasoning {
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

                let result = try await streamingService.continueConversationStreaming(
                    userMessage: userPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema
                )

                let jsonData = try JSONEncoder().encode(result)
                reviewContainer = try JSONDecoder().decode(PhaseReviewContainer.self, from: jsonData)
            } else {
                reviewContainer = try await llm.continueConversationStructured(
                    userMessage: userPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    as: PhaseReviewContainer.self,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema
                )
            }

            phaseReviewState.currentReview = reviewContainer

            if !nextPhase.bundle {
                phaseReviewState.pendingItemIds = reviewContainer.items.map { $0.id }
                phaseReviewState.currentItemIndex = 0
            }

            reasoningStreamManager.hideAndClear()
            isProcessingRevisions = false

        } catch {
            Logger.error("❌ Phase \(nextPhase.phase) failed: \(error.localizedDescription)")
            isProcessingRevisions = false
            await advanceToNextPhase(resume: resume)
        }
    }

    /// Accept current review item and move to next (for unbundled phases).
    func acceptCurrentItemAndMoveNext(resume: Resume, context: ModelContext) {
        guard var currentReview = phaseReviewState.currentReview,
              phaseReviewState.currentItemIndex < currentReview.items.count else { return }

        // Mark current item as accepted
        currentReview.items[phaseReviewState.currentItemIndex].userDecision = .accepted
        phaseReviewState.currentReview = currentReview

        // Move to next item
        phaseReviewState.currentItemIndex += 1

        if phaseReviewState.currentItemIndex >= currentReview.items.count {
            // All items reviewed - complete phase
            completeCurrentPhase(resume: resume, context: context)
        }
    }

    /// Reject current review item and move to next (for unbundled phases).
    func rejectCurrentItemAndMoveNext() {
        guard var currentReview = phaseReviewState.currentReview,
              phaseReviewState.currentItemIndex < currentReview.items.count else { return }

        // Mark current item as rejected
        currentReview.items[phaseReviewState.currentItemIndex].userDecision = .rejected
        phaseReviewState.currentReview = currentReview

        // Move to next item
        phaseReviewState.currentItemIndex += 1
    }

    /// Finish the phase review workflow.
    func finishPhaseReview(resume: Resume) {
        Logger.info("🏁 Phase review complete for '\(phaseReviewState.currentSection)'")
        Logger.info("  - Phases completed: \(phaseReviewState.approvedReviews.count)")

        // Trigger PDF refresh
        exportCoordinator.debounceExport(resume: resume)

        // Clear state and dismiss
        phaseReviewState.reset()
        showResumeRevisionSheet = false
        markWorkflowCompleted(reset: true)
    }

    /// Check if there are unapplied approved changes.
    func hasUnappliedApprovedChanges() -> Bool {
        !phaseReviewState.approvedReviews.isEmpty || phaseReviewState.currentReview != nil
    }

    /// Apply all approved changes and close.
    func applyApprovedChangesAndClose(resume: Resume, context: ModelContext) {
        guard let rootNode = resume.rootNode else { return }

        // Apply any pending current review
        if let currentReview = phaseReviewState.currentReview {
            TreeNode.applyPhaseReviewChanges(currentReview, to: rootNode, context: context)
        }

        // Apply all approved reviews
        for review in phaseReviewState.approvedReviews {
            TreeNode.applyPhaseReviewChanges(review, to: rootNode, context: context)
        }

        // Trigger PDF refresh
        exportCoordinator.debounceExport(resume: resume)

        phaseReviewState.reset()
        showResumeRevisionSheet = false
        markWorkflowCompleted(reset: true)
    }

    /// Discard all changes and close.
    func discardAllAndClose() {
        phaseReviewState.reset()
        showResumeRevisionSheet = false
        markWorkflowCompleted(reset: true)
    }
}
// MARK: - Supporting Types
// MARK: - Note: Using existing types from AITypes.swift and ResumeUpdateNode.swift
// - RevisionsContainer (with revArray property)
// - ClarifyingQuestionsRequest 
// - ClarifyingQuestion
// - QuestionAnswer
