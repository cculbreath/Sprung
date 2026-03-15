//
//  PhaseReviewLLMDispatcher.swift
//  Sprung
//
//  Dispatches phase review LLM calls across the three supported execution paths:
//  reasoning/streaming, tool-enabled, and plain structured.
//  Eliminates the three copy-pasted dispatch blocks that previously lived in PhaseReviewManager.
//

import Foundation
import SwiftOpenAI

/// Dispatches a phase review LLM call across the three supported execution paths:
/// reasoning/streaming, tool-enabled, and plain structured.
@MainActor
struct PhaseReviewLLMDispatcher {
    private let llm: LLMFacade
    private let openRouterService: OpenRouterService
    private let streamingService: RevisionStreamingService
    private let toolRunner: ToolConversationRunner
    private let reasoningStreamManager: ReasoningStreamManager

    init(
        llm: LLMFacade,
        openRouterService: OpenRouterService,
        streamingService: RevisionStreamingService,
        toolRunner: ToolConversationRunner,
        reasoningStreamManager: ReasoningStreamManager
    ) {
        self.llm = llm
        self.openRouterService = openRouterService
        self.streamingService = streamingService
        self.toolRunner = toolRunner
        self.reasoningStreamManager = reasoningStreamManager
    }

    /// Dispatch a review call, returning a parsed PhaseReviewContainer.
    /// Handles all three execution paths internally.
    ///
    /// - Parameters:
    ///   - systemPrompt: The system prompt for the conversation.
    ///   - userPrompt: The user prompt with review instructions.
    ///   - modelId: The model to use.
    ///   - conversationId: Existing conversation ID for continuation paths (nil for new conversations).
    ///   - resume: The resume being reviewed.
    ///   - isNewConversation: True for `startRound` (creates new conversation), false for continuation.
    /// - Returns: The parsed container and an optional new conversation ID (set when a new conversation is created).
    func dispatch(
        systemPrompt: String,
        userPrompt: String,
        modelId: String,
        conversationId: UUID?,
        resume: Resume,
        isNewConversation: Bool
    ) async throws -> (container: PhaseReviewContainer, conversationId: UUID?) {
        let model = openRouterService.findModel(id: modelId)
        let supportsReasoning = model?.supportsReasoning ?? false
        let useTools = toolRunner.shouldUseTools(modelId: modelId, openRouterService: openRouterService)

        Logger.debug("\u{1f916} [LLMDispatch] Model: \(modelId), supportsReasoning: \(supportsReasoning), useTools: \(useTools), isNew: \(isNewConversation)")

        if !supportsReasoning {
            reasoningStreamManager.hideAndClear()
        }

        if supportsReasoning {
            return try await dispatchReasoning(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                modelId: modelId,
                conversationId: conversationId,
                isNewConversation: isNewConversation
            )
        } else if useTools {
            let container = try await dispatchTools(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                modelId: modelId,
                resume: resume
            )
            return (container, nil)
        } else {
            return try await dispatchPlainStructured(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                modelId: modelId,
                conversationId: conversationId,
                isNewConversation: isNewConversation
            )
        }
    }

    // MARK: - Execution Paths

    private func dispatchReasoning(
        systemPrompt: String,
        userPrompt: String,
        modelId: String,
        conversationId: UUID?,
        isNewConversation: Bool
    ) async throws -> (container: PhaseReviewContainer, conversationId: UUID?) {
        let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
        let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

        if isNewConversation {
            Logger.info("\u{1f9e0} Using streaming with reasoning (new conversation): \(modelId)")
            let result = try await streamingService.startConversationStreaming(
                systemPrompt: systemPrompt,
                userMessage: userPrompt,
                modelId: modelId,
                reasoning: reasoning,
                jsonSchema: ResumeApiQuery.phaseReviewSchema,
                as: PhaseReviewContainer.self
            )
            return (result.response, result.conversationId)
        } else {
            guard let conversationId = conversationId else {
                throw LLMError.clientError("No conversation context for reasoning continuation")
            }
            Logger.info("\u{1f9e0} Using streaming with reasoning (continuation): \(modelId)")
            let container = try await streamingService.continueConversationStreaming(
                userMessage: userPrompt,
                modelId: modelId,
                conversationId: conversationId,
                reasoning: reasoning,
                jsonSchema: ResumeApiQuery.phaseReviewSchema,
                as: PhaseReviewContainer.self
            )
            return (container, nil)
        }
    }

    private func dispatchTools(
        systemPrompt: String,
        userPrompt: String,
        modelId: String,
        resume: Resume
    ) async throws -> PhaseReviewContainer {
        Logger.info("\u{1f527} [Tools] Using tool-enabled conversation: \(modelId)")

        let toolSystemPrompt = systemPrompt + buildToolSystemPromptAddendum()

        let finalResponse = try await toolRunner.runConversation(
            systemPrompt: toolSystemPrompt,
            userPrompt: userPrompt + "\n\nPlease provide your review proposals in the specified JSON format.",
            modelId: modelId,
            resume: resume,
            jobApp: nil
        )

        return try JSONResponseParser.parseFlexibleFromText(finalResponse, as: PhaseReviewContainer.self)
    }

    private func dispatchPlainStructured(
        systemPrompt: String,
        userPrompt: String,
        modelId: String,
        conversationId: UUID?,
        isNewConversation: Bool
    ) async throws -> (container: PhaseReviewContainer, conversationId: UUID?) {
        if isNewConversation {
            Logger.info("\u{1f4dd} Using non-streaming (new conversation): \(modelId)")
            let (newConversationId, _) = try await llm.startConversation(
                systemPrompt: systemPrompt,
                userMessage: userPrompt,
                modelId: modelId
            )

            let container = try await llm.continueConversationStructured(
                userMessage: "Please provide your review proposals in the specified JSON format.",
                modelId: modelId,
                conversationId: newConversationId,
                as: PhaseReviewContainer.self,
                jsonSchema: ResumeApiQuery.phaseReviewSchema
            )
            return (container, newConversationId)
        } else {
            guard let conversationId = conversationId else {
                throw LLMError.clientError("No conversation context for structured continuation")
            }
            Logger.info("\u{1f4dd} Using non-streaming (continuation): \(modelId)")
            let container = try await llm.continueConversationStructured(
                userMessage: userPrompt,
                modelId: modelId,
                conversationId: conversationId,
                as: PhaseReviewContainer.self,
                jsonSchema: ResumeApiQuery.phaseReviewSchema
            )
            return (container, nil)
        }
    }

    // MARK: - Helpers

    /// Build system prompt augmentation for tool-enabled phase review
    private func buildToolSystemPromptAddendum() -> String {
        return """

            You have access to tools that can provide additional context.
            Use any available tools when you need more information to make informed review proposals.

            After gathering any needed information via tools, provide your review proposals
            in the specified JSON format.
            """
    }
}
