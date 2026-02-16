//
//  CustomizationParallelExecutor.swift
//  Sprung
//
//  Manages concurrent execution of resume customization revision tasks.
//  Limits concurrency to avoid overwhelming the API and provides
//  streaming results as tasks complete.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

// MARK: - Supporting Types

/// Type of revision for node-specific behavior
enum RevisionNodeType: String, Sendable {
    case skills          // Skills section (categories from LLM, skills from bank)
    case skillKeywords   // Individual skill category keywords
    case titles          // Title node (select from title set library)
    case generic         // Standard revision
    case compound        // Multiple related fields revised together
}

/// A revision task to execute
struct RevisionTask: Identifiable, Sendable, Equatable {
    let id: UUID
    let revNode: ExportedReviewNode  // The node being revised
    let taskPrompt: String           // Task-specific prompt
    let nodeType: RevisionNodeType   // Type of revision
    let phase: Int                   // Phase number (1 or 2)

    init(
        id: UUID = UUID(),
        revNode: ExportedReviewNode,
        taskPrompt: String,
        nodeType: RevisionNodeType = .generic,
        phase: Int = 1
    ) {
        self.id = id
        self.revNode = revNode
        self.taskPrompt = taskPrompt
        self.nodeType = nodeType
        self.phase = phase
    }
}

/// Result of task execution
struct RevisionTaskResult: Sendable {
    let taskId: UUID
    let result: Result<ProposedRevisionNode, Error>
    /// For compound tasks, contains the individual field revisions
    let compoundResults: [ProposedRevisionNode]?

    init(taskId: UUID, result: Result<ProposedRevisionNode, Error>, compoundResults: [ProposedRevisionNode]? = nil) {
        self.taskId = taskId
        self.result = result
        self.compoundResults = compoundResults
    }
}

/// Response format for compound revision tasks
struct CompoundRevisionResponse: Codable, Sendable {
    let compoundFields: [ProposedRevisionNode]
}

// MARK: - Tool Configuration

/// Configuration for tool-enabled execution in the parallel executor.
/// Bundles tool definitions with a closure that executes tool calls,
/// allowing the actor to invoke tools without depending on @MainActor types directly.
struct ToolConfiguration: Sendable {
    /// Tool definitions for the LLM request
    let tools: [ChatCompletionParameters.Tool]

    /// Closure that executes a named tool with JSON arguments and returns the result string.
    /// The closure bridges to @MainActor tool registries as needed.
    let executeTool: @Sendable (String, String) async throws -> String

    /// Maximum number of tool call rounds before forcing a final response (default: 3)
    let maxToolRounds: Int

    init(
        tools: [ChatCompletionParameters.Tool],
        executeTool: @escaping @Sendable (String, String) async throws -> String,
        maxToolRounds: Int = 3
    ) {
        self.tools = tools
        self.executeTool = executeTool
        self.maxToolRounds = maxToolRounds
    }
}

// MARK: - Parallel Executor

/// Actor that manages parallel execution of resume revision tasks.
/// Limits concurrency and streams results as they complete.
actor CustomizationParallelExecutor {
    // MARK: - Configuration

    private let maxConcurrent: Int
    /// Maximum number of retry attempts when JSON decoding fails
    private let maxJSONRetries = 5

    // MARK: - State

    private var runningCount = 0
    private var waitQueue: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []

    // MARK: - Init

    init(maxConcurrent: Int = 5) {
        self.maxConcurrent = maxConcurrent
    }

    // MARK: - Public API

    /// Execute multiple revision tasks in parallel with concurrency limiting.
    /// Returns an AsyncStream that yields results as tasks complete.
    /// - Parameters:
    ///   - tasks: The revision tasks to execute
    ///   - llmFacade: The LLM facade for API calls
    ///   - modelId: The model ID to use
    ///   - preamble: The preamble to prepend to each task prompt (legacy single-string mode)
    ///   - systemPrompt: Optional system message (for split preamble mode). When provided,
    ///     preamble is used only for the user message variable context.
    ///   - toolConfig: Optional tool configuration for tool-enabled execution
    ///   - reasoning: Optional reasoning config for extended thinking
    ///   - onReasoningChunk: Callback for reasoning text deltas (taskId, text)
    /// - Returns: AsyncStream of task results
    func execute(
        tasks: [RevisionTask],
        llmFacade: LLMFacade,
        modelId: String,
        preamble: String,
        systemPrompt: String? = nil,
        toolConfig: ToolConfiguration? = nil,
        reasoning: OpenRouterReasoning? = nil,
        onReasoningChunk: (@Sendable (UUID, String) async -> Void)? = nil
    ) -> AsyncStream<RevisionTaskResult> {
        AsyncStream { continuation in
            Task {
                await withTaskGroup(of: RevisionTaskResult.self) { group in
                    for task in tasks {
                        // Wait if at max concurrency
                        await self.waitForSlot()

                        group.addTask {
                            let result = await self.executeTaskInternal(
                                task: task,
                                llmFacade: llmFacade,
                                modelId: modelId,
                                preamble: preamble,
                                systemPrompt: systemPrompt,
                                toolConfig: toolConfig,
                                reasoning: reasoning,
                                onReasoningChunk: onReasoningChunk
                            )
                            await self.releaseSlot()
                            return result
                        }
                    }

                    // Yield results as they complete
                    for await result in group {
                        continuation.yield(result)
                    }
                }

                continuation.finish()
            }
        }
    }

    /// Execute a single revision task (convenience method)
    func executeSingle(
        task: RevisionTask,
        llmFacade: LLMFacade,
        modelId: String,
        preamble: String,
        systemPrompt: String? = nil,
        toolConfig: ToolConfiguration? = nil,
        reasoning: OpenRouterReasoning? = nil,
        onReasoningChunk: (@Sendable (UUID, String) async -> Void)? = nil
    ) async -> RevisionTaskResult {
        await waitForSlot()

        let result = await executeTaskInternal(
            task: task,
            llmFacade: llmFacade,
            modelId: modelId,
            preamble: preamble,
            systemPrompt: systemPrompt,
            toolConfig: toolConfig,
            reasoning: reasoning,
            onReasoningChunk: onReasoningChunk
        )
        await releaseSlot()
        return result
    }

    // MARK: - Internal Execution

    private func executeTaskInternal(
        task: RevisionTask,
        llmFacade: LLMFacade,
        modelId: String,
        preamble: String,
        systemPrompt: String? = nil,
        toolConfig: ToolConfiguration? = nil,
        reasoning: OpenRouterReasoning? = nil,
        onReasoningChunk: (@Sendable (UUID, String) async -> Void)? = nil
    ) async -> RevisionTaskResult {
        do {
            // Build user-message content (variable context + task prompt + node info)
            let userPrompt = buildFullPrompt(preamble: preamble, task: task)

            if task.nodeType == .compound {
                // Compound task: parse as CompoundRevisionResponse
                if let reasoning, toolConfig == nil {
                    return try await executeCompoundTaskStreaming(
                        task: task,
                        fullPrompt: userPrompt,
                        llmFacade: llmFacade,
                        modelId: modelId,
                        systemPrompt: systemPrompt,
                        reasoning: reasoning,
                        onReasoningChunk: onReasoningChunk
                    )
                }
                return try await executeCompoundTask(
                    task: task,
                    fullPrompt: userPrompt,
                    llmFacade: llmFacade,
                    modelId: modelId,
                    systemPrompt: systemPrompt,
                    toolConfig: toolConfig
                )
            }

            if let toolConfig {
                // Tool-enabled path: conversation loop with tool calls (skip reasoning)
                let response = try await executeWithToolLoop(
                    prompt: userPrompt,
                    llmFacade: llmFacade,
                    modelId: modelId,
                    systemPrompt: systemPrompt,
                    toolConfig: toolConfig
                )
                return RevisionTaskResult(
                    taskId: task.id,
                    result: .success(response)
                )
            }

            // Streaming path with reasoning
            if let reasoning {
                return try await executeWithStreaming(
                    task: task,
                    fullPrompt: userPrompt,
                    llmFacade: llmFacade,
                    modelId: modelId,
                    systemPrompt: systemPrompt,
                    reasoning: reasoning,
                    onReasoningChunk: onReasoningChunk
                )
            }

            // Non-tool, non-reasoning path: single-shot structured output via messages
            if let systemPrompt {
                let response = try await executeStructuredWithMessages(
                    userPrompt: userPrompt,
                    systemPrompt: systemPrompt,
                    llmFacade: llmFacade,
                    modelId: modelId,
                    schema: CustomizationSchemas.proposedRevisionNode,
                    schemaName: "proposed_revision_node",
                    type: ProposedRevisionNode.self
                )
                return RevisionTaskResult(
                    taskId: task.id,
                    result: .success(response)
                )
            }

            // Legacy single-prompt path (no system prompt split)
            let response = try await llmFacade.executeStructuredWithSchema(
                prompt: userPrompt,
                modelId: modelId,
                as: ProposedRevisionNode.self,
                schema: CustomizationSchemas.proposedRevisionNode,
                schemaName: "proposed_revision_node"
            )
            return RevisionTaskResult(
                taskId: task.id,
                result: .success(response)
            )
        } catch {
            return RevisionTaskResult(
                taskId: task.id,
                result: .failure(error)
            )
        }
    }

    // MARK: - Streaming Execution

    /// Execute a single task with streaming to capture reasoning tokens.
    private func executeWithStreaming(
        task: RevisionTask,
        fullPrompt: String,
        llmFacade: LLMFacade,
        modelId: String,
        systemPrompt: String? = nil,
        reasoning: OpenRouterReasoning,
        onReasoningChunk: (@Sendable (UUID, String) async -> Void)?
    ) async throws -> RevisionTaskResult {
        let handle = try await llmFacade.executeStructuredStreaming(
            prompt: fullPrompt,
            modelId: modelId,
            as: ProposedRevisionNode.self,
            reasoning: reasoning,
            jsonSchema: CustomizationSchemas.proposedRevisionNode,
            systemPrompt: systemPrompt
        )

        var accumulatedJSON = ""
        for try await chunk in handle.stream {
            if let reasoningText = chunk.allReasoningText, !reasoningText.isEmpty {
                await onReasoningChunk?(task.id, reasoningText)
            }
            if let content = chunk.content {
                accumulatedJSON += content
            }
        }

        guard !accumulatedJSON.isEmpty else {
            throw LLMError.clientError("Streaming produced empty response for task \(task.revNode.displayName)")
        }

        let response = try await decodeWithRetry(
            ProposedRevisionNode.self,
            from: accumulatedJSON,
            originalPrompt: fullPrompt,
            llmFacade: llmFacade,
            modelId: modelId,
            schema: CustomizationSchemas.proposedRevisionNode,
            schemaName: "proposed_revision_node"
        )
        return RevisionTaskResult(taskId: task.id, result: .success(response))
    }

    /// Execute a compound task with streaming to capture reasoning tokens.
    private func executeCompoundTaskStreaming(
        task: RevisionTask,
        fullPrompt: String,
        llmFacade: LLMFacade,
        modelId: String,
        systemPrompt: String? = nil,
        reasoning: OpenRouterReasoning,
        onReasoningChunk: (@Sendable (UUID, String) async -> Void)?
    ) async throws -> RevisionTaskResult {
        let handle = try await llmFacade.executeStructuredStreaming(
            prompt: fullPrompt,
            modelId: modelId,
            as: CompoundRevisionResponse.self,
            reasoning: reasoning,
            jsonSchema: CustomizationSchemas.compoundRevisionResponse,
            systemPrompt: systemPrompt
        )

        var accumulatedJSON = ""
        for try await chunk in handle.stream {
            if let reasoningText = chunk.allReasoningText, !reasoningText.isEmpty {
                await onReasoningChunk?(task.id, reasoningText)
            }
            if let content = chunk.content {
                accumulatedJSON += content
            }
        }

        guard !accumulatedJSON.isEmpty else {
            throw LLMError.clientError("Streaming produced empty response for compound task \(task.revNode.displayName)")
        }

        let compoundResponse = try await decodeWithRetry(
            CompoundRevisionResponse.self,
            from: accumulatedJSON,
            originalPrompt: fullPrompt,
            llmFacade: llmFacade,
            modelId: modelId,
            schema: CustomizationSchemas.compoundRevisionResponse,
            schemaName: "compound_revision_response"
        )
        let results = compoundResponse.compoundFields
        let primary = results.first ?? ProposedRevisionNode()
        return RevisionTaskResult(taskId: task.id, result: .success(primary), compoundResults: results)
    }

    /// Execute a compound task that produces multiple field revisions.
    private func executeCompoundTask(
        task: RevisionTask,
        fullPrompt: String,
        llmFacade: LLMFacade,
        modelId: String,
        systemPrompt: String? = nil,
        toolConfig: ToolConfiguration?
    ) async throws -> RevisionTaskResult {
        let compoundResponse: CompoundRevisionResponse
        if let systemPrompt {
            compoundResponse = try await executeStructuredWithMessages(
                userPrompt: fullPrompt,
                systemPrompt: systemPrompt,
                llmFacade: llmFacade,
                modelId: modelId,
                schema: CustomizationSchemas.compoundRevisionResponse,
                schemaName: "compound_revision_response",
                type: CompoundRevisionResponse.self
            )
        } else {
            compoundResponse = try await llmFacade.executeStructuredWithSchema(
                prompt: fullPrompt,
                modelId: modelId,
                as: CompoundRevisionResponse.self,
                schema: CustomizationSchemas.compoundRevisionResponse,
                schemaName: "compound_revision_response"
            )
        }
        let results = compoundResponse.compoundFields
        let primary = results.first ?? ProposedRevisionNode()
        return RevisionTaskResult(
            taskId: task.id,
            result: .success(primary),
            compoundResults: results
        )
    }

    // MARK: - Tool-Enabled Execution

    /// Execute a task using a conversation loop that supports tool calls.
    /// The LLM can invoke tools (e.g., ReadKnowledgeCardsTool) to retrieve
    /// additional context before producing the final ProposedRevisionNode JSON.
    private func executeWithToolLoop(
        prompt: String,
        llmFacade: LLMFacade,
        modelId: String,
        systemPrompt: String? = nil,
        toolConfig: ToolConfiguration
    ) async throws -> ProposedRevisionNode {
        let responseFormat: ResponseFormat = .jsonSchema(
            JSONSchemaResponseFormat(
                name: "proposed_revision_node",
                strict: true,
                schema: CustomizationSchemas.proposedRevisionNode
            )
        )

        // When systemPrompt is provided, use cachedText for cache_control.
        // Otherwise fall back to a generic system instruction.
        let systemMessage: ChatCompletionParameters.Message
        if let systemPrompt {
            let cacheControl = ChatCompletionParameters.Message.ContentType.MessageContent.CacheControl()
            systemMessage = .init(role: .system, content: .contentArray([.cachedText(systemPrompt, cacheControl)]))
        } else {
            systemMessage = .init(role: .system, content: .text(
                "You are a resume customization assistant. Use the available tools to gather " +
                "any needed context before producing your revision response."
            ))
        }

        var messages: [ChatCompletionParameters.Message] = [
            systemMessage,
            .init(role: .user, content: .text(prompt))
        ]

        var remainingRounds = toolConfig.maxToolRounds

        while remainingRounds > 0 {
            remainingRounds -= 1

            let response = try await llmFacade.executeWithTools(
                messages: messages,
                tools: toolConfig.tools,
                toolChoice: .auto,
                modelId: modelId,
                responseFormat: responseFormat
            )

            guard let choice = response.choices?.first,
                  let message = choice.message else {
                throw LLMError.clientError("No response from model during tool conversation")
            }

            // Check for tool calls
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                Logger.info("[ParallelExecutor] Model requested \(toolCalls.count) tool call(s), round \(toolConfig.maxToolRounds - remainingRounds)", category: .ai)

                // Add assistant message with tool calls to history
                let assistantContent: ChatCompletionParameters.Message.ContentType =
                    message.content.map { .text($0) } ?? .text("")
                messages.append(ChatCompletionParameters.Message(
                    role: .assistant,
                    content: assistantContent,
                    toolCalls: toolCalls
                ))

                // Execute each tool call and add results
                for toolCall in toolCalls {
                    let toolCallId = toolCall.id ?? UUID().uuidString
                    let toolName = toolCall.function.name ?? "unknown"
                    let toolArguments = toolCall.function.arguments

                    Logger.debug("[ParallelExecutor] Executing tool: \(toolName)", category: .ai)

                    let resultString: String
                    do {
                        resultString = try await toolConfig.executeTool(toolName, toolArguments)
                    } catch {
                        resultString = "{\"error\": \"\(error.localizedDescription)\"}"
                        Logger.warning("[ParallelExecutor] Tool execution error: \(error.localizedDescription)", category: .ai)
                    }

                    messages.append(ChatCompletionParameters.Message(
                        role: .tool,
                        content: .text(resultString),
                        toolCallID: toolCallId
                    ))
                }
            } else {
                // No tool calls - parse the final response as ProposedRevisionNode
                let finalContent = message.content ?? ""
                Logger.info("[ParallelExecutor] Tool conversation complete after \(toolConfig.maxToolRounds - remainingRounds) round(s)", category: .ai)
                return try await decodeWithRetry(
                    ProposedRevisionNode.self,
                    from: finalContent,
                    originalPrompt: prompt,
                    llmFacade: llmFacade,
                    modelId: modelId,
                    schema: CustomizationSchemas.proposedRevisionNode,
                    schemaName: "proposed_revision_node"
                )
            }
        }

        // Exhausted tool rounds - make one final call without tools to force a JSON response
        Logger.warning("[ParallelExecutor] Exhausted \(toolConfig.maxToolRounds) tool rounds, forcing final response", category: .ai)

        let finalResponse = try await llmFacade.executeWithTools(
            messages: messages,
            tools: [],
            toolChoice: .none,
            modelId: modelId,
            responseFormat: responseFormat
        )

        guard let finalChoice = finalResponse.choices?.first,
              let finalMessage = finalChoice.message,
              let finalContent = finalMessage.content else {
            throw LLMError.clientError("No final response after exhausting tool rounds")
        }

        return try await decodeWithRetry(
            ProposedRevisionNode.self,
            from: finalContent,
            originalPrompt: prompt,
            llmFacade: llmFacade,
            modelId: modelId,
            schema: CustomizationSchemas.proposedRevisionNode,
            schemaName: "proposed_revision_node"
        )
    }

    /// Execute a structured request using separate system/user messages via executeWithTools.
    /// Uses content array with cache_control on the system message for provider-side prompt caching.
    private func executeStructuredWithMessages<T: Codable & Sendable>(
        userPrompt: String,
        systemPrompt: String,
        llmFacade: LLMFacade,
        modelId: String,
        schema: JSONSchema,
        schemaName: String,
        type: T.Type
    ) async throws -> T {
        let responseFormat: ResponseFormat = .jsonSchema(
            JSONSchemaResponseFormat(
                name: schemaName,
                strict: true,
                schema: schema
            )
        )

        // System message uses cachedText for cache_control breakpoint.
        // This tells OpenRouter/Anthropic to cache the system prompt across requests.
        let cacheControl = ChatCompletionParameters.Message.ContentType.MessageContent.CacheControl()
        let messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .contentArray([.cachedText(systemPrompt, cacheControl)])),
            .init(role: .user, content: .text(userPrompt))
        ]

        let response = try await llmFacade.executeWithTools(
            messages: messages,
            tools: [],
            toolChoice: nil,
            modelId: modelId,
            responseFormat: responseFormat
        )

        guard let content = response.choices?.first?.message?.content else {
            throw LLMError.clientError("Empty response from structured message request")
        }

        return try await decodeWithRetry(
            T.self,
            from: content,
            originalPrompt: userPrompt,
            llmFacade: llmFacade,
            modelId: modelId,
            schema: schema,
            schemaName: schemaName
        )
    }

    private func buildFullPrompt(
        preamble: String,
        task: RevisionTask
    ) -> String {
        // Preamble already contains job description, applicant profile, knowledge cards,
        // skill bank, and all other shared context. Only append task-specific content.
        var prompt = preamble

        // Add task-specific prompt
        prompt += "\n\n## Task\n\(task.taskPrompt)"

        // Add node information
        prompt += "\n\n## Node to Revise\n"
        prompt += "ID: \(task.revNode.id)\n"
        prompt += "Path: \(task.revNode.path)\n"
        prompt += "Display Name: \(task.revNode.displayName)\n"
        prompt += "Current Value: \(task.revNode.value)\n"

        if let childValues = task.revNode.childValues, !childValues.isEmpty {
            prompt += "Child Values: \(childValues.joined(separator: ", "))\n"
        }

        return prompt
    }

    // MARK: - JSON Decode Retry

    /// Build a descriptive error message from a JSON decoding failure.
    private func describeDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return "JSON parsing error: \(error.localizedDescription)"
        }

        switch decodingError {
        case .typeMismatch(let type, let context):
            return "Type mismatch: Expected \(type) at path '\(context.codingPath.map(\.stringValue).joined(separator: "."))'. \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Missing value: Expected \(type) at path '\(context.codingPath.map(\.stringValue).joined(separator: "."))'. \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "Missing key: '\(key.stringValue)' not found at path '\(context.codingPath.map(\.stringValue).joined(separator: "."))'. \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "Data corrupted at path '\(context.codingPath.map(\.stringValue).joined(separator: "."))'. \(context.debugDescription)"
        @unknown default:
            return "Decoding error: \(decodingError.localizedDescription)"
        }
    }

    /// Attempt to decode JSON from the LLM response. On failure, send the error back
    /// to the LLM as a conversational turn and let it regenerate — up to `maxJSONRetries` times.
    ///
    /// The retry is a multi-turn conversation: the LLM sees its own bad output, the specific
    /// parse error, and produces a fresh response. No local parsing hacks.
    private func decodeWithRetry<T: Codable & Sendable>(
        _ type: T.Type,
        from rawJSON: String,
        originalPrompt: String,
        llmFacade: LLMFacade,
        modelId: String,
        schema: JSONSchema,
        schemaName: String
    ) async throws -> T {
        // First attempt: direct decode
        guard let data = rawJSON.data(using: .utf8) else {
            throw LLMError.clientError("Failed to convert response to UTF-8 data")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let firstError {
            Logger.warning("[ParallelExecutor] JSON decode failed, will retry via conversation: \(firstError.localizedDescription)", category: .ai)

            // Build the conversation thread for retries.
            // Each retry appends the LLM's bad output + our error feedback,
            // then the LLM generates a fresh response in context.
            let responseFormat: ResponseFormat = .jsonSchema(
                JSONSchemaResponseFormat(
                    name: schemaName,
                    strict: true,
                    schema: schema
                )
            )

            var messages: [ChatCompletionParameters.Message] = [
                .init(role: .system, content: .text(
                    "You are a resume customization assistant. You MUST respond with valid JSON matching the required schema."
                )),
                .init(role: .user, content: .text(originalPrompt))
            ]

            var lastBadJSON = rawJSON
            var lastError: Error = firstError

            for attempt in 1...maxJSONRetries {
                // Add the LLM's bad response as an assistant turn
                messages.append(.init(role: .assistant, content: .text(lastBadJSON)))

                // Add our error feedback as a user turn
                let errorFeedback = """
                Your response could not be parsed as valid JSON. \
                \(describeDecodingError(lastError))

                Please respond again with corrected JSON matching the required schema exactly. \
                (Retry \(attempt) of \(maxJSONRetries))
                """
                messages.append(.init(role: .user, content: .text(errorFeedback)))

                Logger.info("[ParallelExecutor] Requesting JSON correction via conversation (attempt \(attempt)/\(maxJSONRetries))", category: .ai)

                // Call the LLM — capture raw content separately from decode
                let response: ChatCompletionObject
                do {
                    response = try await llmFacade.executeWithTools(
                        messages: messages,
                        tools: [],
                        toolChoice: nil,
                        modelId: modelId,
                        responseFormat: responseFormat
                    )
                } catch {
                    // Network/API error — not a JSON issue, propagate immediately
                    Logger.error("[ParallelExecutor] LLM call failed on correction attempt \(attempt): \(error.localizedDescription)", category: .ai)
                    throw error
                }

                guard let content = response.choices?.first?.message?.content,
                      let responseData = content.data(using: .utf8) else {
                    lastBadJSON = "(empty response)"
                    lastError = LLMError.clientError("Empty response on JSON correction attempt \(attempt)")
                    Logger.warning("[ParallelExecutor] Empty response on correction attempt \(attempt)", category: .ai)
                    continue
                }

                // Try to decode the new response
                do {
                    let decoded = try JSONDecoder().decode(T.self, from: responseData)
                    Logger.info("[ParallelExecutor] JSON correction succeeded on attempt \(attempt)", category: .ai)
                    return decoded
                } catch let decodeError {
                    // Decode failed again — feed this back into the next iteration
                    lastBadJSON = content
                    lastError = decodeError
                    Logger.warning("[ParallelExecutor] JSON correction attempt \(attempt) decode failed: \(decodeError.localizedDescription)", category: .ai)
                }
            }

            Logger.error("[ParallelExecutor] JSON decode failed after \(maxJSONRetries) correction attempts", category: .ai)
            throw lastError
        }
    }

    // MARK: - Concurrency Control

    private func waitForSlot() async {
        if runningCount < maxConcurrent {
            runningCount += 1
            return
        }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waitQueue.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
        // Slot was handed to us by releaseSlot — runningCount already accounts for it
    }

    /// Remove a cancelled waiter from the queue without waking it (already resumed by cancellation handler).
    private func cancelWaiter(id: UUID) {
        if let index = waitQueue.firstIndex(where: { $0.id == id }) {
            let entry = waitQueue.remove(at: index)
            entry.continuation.resume()
        }
    }

    private func releaseSlot() {
        if let next = waitQueue.first {
            // Hand the slot directly to the next waiter (runningCount stays the same)
            waitQueue.removeFirst()
            next.continuation.resume()
        } else {
            guard runningCount > 0 else {
                Logger.warning("releaseSlot called with runningCount at 0", category: .ai)
                return
            }
            runningCount -= 1
        }
    }

    /// Current number of running tasks
    var currentRunningCount: Int {
        runningCount
    }

    /// Whether any tasks are running
    var isRunning: Bool {
        runningCount > 0
    }
}

// MARK: - Batch Execution Helper

extension CustomizationParallelExecutor {
    /// Execute all tasks and collect results.
    /// Useful when you need all results before proceeding.
    /// - Parameters:
    ///   - tasks: The revision tasks to execute
    ///   - llmFacade: The LLM facade for API calls
    ///   - modelId: The model ID to use
    ///   - preamble: The preamble to prepend to each task prompt
    ///   - toolConfig: Optional tool configuration for tool-enabled execution
    /// - Returns: Dictionary mapping task IDs to results
    func executeAll(
        tasks: [RevisionTask],
        llmFacade: LLMFacade,
        modelId: String,
        preamble: String,
        systemPrompt: String? = nil,
        toolConfig: ToolConfiguration? = nil,
        reasoning: OpenRouterReasoning? = nil,
        onReasoningChunk: (@Sendable (UUID, String) async -> Void)? = nil
    ) async -> [UUID: Result<ProposedRevisionNode, Error>] {
        var results: [UUID: Result<ProposedRevisionNode, Error>] = [:]

        let stream = execute(
            tasks: tasks,
            llmFacade: llmFacade,
            modelId: modelId,
            preamble: preamble,
            systemPrompt: systemPrompt,
            toolConfig: toolConfig,
            reasoning: reasoning,
            onReasoningChunk: onReasoningChunk
        )

        for await taskResult in stream {
            results[taskResult.taskId] = taskResult.result
        }

        return results
    }
}
