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

// MARK: - Parallel Execution Context

/// Lightweight context for parallel execution operations.
/// Contains serializable strings for use in concurrent tasks.
struct ParallelExecutionContext: Sendable {
    let jobPosting: String
    let resumeSnapshot: String
    let applicantProfile: String
    let additionalContext: String

    init(
        jobPosting: String = "",
        resumeSnapshot: String = "",
        applicantProfile: String = "",
        additionalContext: String = ""
    ) {
        self.jobPosting = jobPosting
        self.resumeSnapshot = resumeSnapshot
        self.applicantProfile = applicantProfile
        self.additionalContext = additionalContext
    }
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

    // MARK: - State

    private var runningCount = 0
    private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]

    // MARK: - Init

    init(maxConcurrent: Int = 5) {
        self.maxConcurrent = maxConcurrent
    }

    // MARK: - Public API

    /// Execute multiple revision tasks in parallel with concurrency limiting.
    /// Returns an AsyncStream that yields results as tasks complete.
    /// - Parameters:
    ///   - tasks: The revision tasks to execute
    ///   - context: The customization context
    ///   - llmFacade: The LLM facade for API calls
    ///   - modelId: The model ID to use
    ///   - preamble: The preamble to prepend to each task prompt
    ///   - toolConfig: Optional tool configuration for tool-enabled execution
    /// - Returns: AsyncStream of task results
    func execute(
        tasks: [RevisionTask],
        context: ParallelExecutionContext,
        llmFacade: LLMFacade,
        modelId: String,
        preamble: String,
        toolConfig: ToolConfiguration? = nil
    ) -> AsyncStream<RevisionTaskResult> {
        AsyncStream { continuation in
            Task {
                await withTaskGroup(of: RevisionTaskResult.self) { group in
                    for task in tasks {
                        // Wait if at max concurrency
                        await self.waitForSlot()

                        group.addTask {
                            defer {
                                Task { await self.releaseSlot() }
                            }

                            return await self.executeTaskInternal(
                                task: task,
                                context: context,
                                llmFacade: llmFacade,
                                modelId: modelId,
                                preamble: preamble,
                                toolConfig: toolConfig
                            )
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
        context: ParallelExecutionContext,
        llmFacade: LLMFacade,
        modelId: String,
        preamble: String,
        toolConfig: ToolConfiguration? = nil
    ) async -> RevisionTaskResult {
        await waitForSlot()
        defer {
            Task { await self.releaseSlot() }
        }

        return await executeTaskInternal(
            task: task,
            context: context,
            llmFacade: llmFacade,
            modelId: modelId,
            preamble: preamble,
            toolConfig: toolConfig
        )
    }

    // MARK: - Internal Execution

    private func executeTaskInternal(
        task: RevisionTask,
        context: ParallelExecutionContext,
        llmFacade: LLMFacade,
        modelId: String,
        preamble: String,
        toolConfig: ToolConfiguration? = nil
    ) async -> RevisionTaskResult {
        do {
            let fullPrompt = buildFullPrompt(preamble: preamble, task: task, context: context)

            if task.nodeType == .compound {
                // Compound task: parse as CompoundRevisionResponse
                return try await executeCompoundTask(
                    task: task,
                    fullPrompt: fullPrompt,
                    llmFacade: llmFacade,
                    modelId: modelId,
                    toolConfig: toolConfig
                )
            }

            if let toolConfig {
                // Tool-enabled path: conversation loop with tool calls
                let response = try await executeWithToolLoop(
                    prompt: fullPrompt,
                    llmFacade: llmFacade,
                    modelId: modelId,
                    toolConfig: toolConfig
                )
                return RevisionTaskResult(
                    taskId: task.id,
                    result: .success(response)
                )
            } else {
                // Non-tool path: single-shot flexible JSON (existing behavior)
                let response = try await llmFacade.executeFlexibleJSON(
                    prompt: fullPrompt,
                    modelId: modelId,
                    as: ProposedRevisionNode.self
                )
                return RevisionTaskResult(
                    taskId: task.id,
                    result: .success(response)
                )
            }
        } catch {
            return RevisionTaskResult(
                taskId: task.id,
                result: .failure(error)
            )
        }
    }

    /// Execute a compound task that produces multiple field revisions.
    private func executeCompoundTask(
        task: RevisionTask,
        fullPrompt: String,
        llmFacade: LLMFacade,
        modelId: String,
        toolConfig: ToolConfiguration?
    ) async throws -> RevisionTaskResult {
        // First try to decode as CompoundRevisionResponse directly
        do {
            let compoundResponse = try await llmFacade.executeFlexibleJSON(
                prompt: fullPrompt,
                modelId: modelId,
                as: CompoundRevisionResponse.self
            )
            let results = compoundResponse.compoundFields
            let primary = results.first ?? ProposedRevisionNode()
            return RevisionTaskResult(
                taskId: task.id,
                result: .success(primary),
                compoundResults: results
            )
        } catch {
            Logger.debug("[ParallelExecutor] CompoundRevisionResponse decode failed, trying single ProposedRevisionNode fallback", category: .ai)
        }

        // Fallback: try as a single ProposedRevisionNode
        let single = try await llmFacade.executeFlexibleJSON(
            prompt: fullPrompt,
            modelId: modelId,
            as: ProposedRevisionNode.self
        )
        return RevisionTaskResult(
            taskId: task.id,
            result: .success(single),
            compoundResults: [single]
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
        toolConfig: ToolConfiguration
    ) async throws -> ProposedRevisionNode {
        // Build initial messages: system prompt (preamble + context) as a user message
        // since executeWithTools takes raw messages
        var messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text(
                "You are a resume customization assistant. After gathering any needed context via tools, " +
                "respond with a single JSON object matching the ProposedRevisionNode schema: " +
                "{\"id\": string, \"oldValue\": string, \"newValue\": string, \"valueChanged\": bool, " +
                "\"isTitleNode\": bool, \"why\": string, \"treePath\": string, " +
                "\"nodeType\": \"scalar\"|\"list\", \"oldValueArray\": [string]?, \"newValueArray\": [string]?}"
            )),
            .init(role: .user, content: .text(prompt))
        ]

        var remainingRounds = toolConfig.maxToolRounds

        while remainingRounds > 0 {
            remainingRounds -= 1

            let response = try await llmFacade.executeWithTools(
                messages: messages,
                tools: toolConfig.tools,
                toolChoice: .auto,
                modelId: modelId
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
                return try parseProposedRevisionNode(from: finalContent)
            }
        }

        // Exhausted tool rounds - make one final call without tools to force a JSON response
        Logger.warning("[ParallelExecutor] Exhausted \(toolConfig.maxToolRounds) tool rounds, forcing final response", category: .ai)

        let finalResponse = try await llmFacade.executeWithTools(
            messages: messages,
            tools: [],
            toolChoice: .none,
            modelId: modelId
        )

        guard let finalChoice = finalResponse.choices?.first,
              let finalMessage = finalChoice.message,
              let finalContent = finalMessage.content else {
            throw LLMError.clientError("No final response after exhausting tool rounds")
        }

        return try parseProposedRevisionNode(from: finalContent)
    }

    /// Parse a ProposedRevisionNode from a raw LLM response string.
    /// Handles responses that may include markdown code fences or extra text around JSON.
    private func parseProposedRevisionNode(from response: String) throws -> ProposedRevisionNode {
        // Try to extract JSON object from the response
        let jsonString: String
        if let jsonStart = response.range(of: "{"),
           let jsonEnd = response.range(of: "}", options: .backwards) {
            jsonString = String(response[jsonStart.lowerBound...jsonEnd.upperBound])
        } else {
            jsonString = response
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw LLMError.clientError("Failed to convert tool conversation response to data")
        }

        return try JSONDecoder().decode(ProposedRevisionNode.self, from: data)
    }

    private func buildFullPrompt(
        preamble: String,
        task: RevisionTask,
        context: ParallelExecutionContext
    ) -> String {
        var prompt = preamble

        // Add context sections if available
        if !context.jobPosting.isEmpty {
            prompt += "\n\n## Job Posting\n\(context.jobPosting)"
        }

        if !context.resumeSnapshot.isEmpty {
            prompt += "\n\n## Current Resume\n\(context.resumeSnapshot)"
        }

        if !context.applicantProfile.isEmpty {
            prompt += "\n\n## Applicant Profile\n\(context.applicantProfile)"
        }

        if !context.additionalContext.isEmpty {
            prompt += "\n\n## Additional Context\n\(context.additionalContext)"
        }

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

    // MARK: - Concurrency Control

    private func waitForSlot() async {
        if runningCount >= maxConcurrent {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let id = UUID()
                continuations[id] = continuation
            }
        }
        runningCount += 1
    }

    private func releaseSlot() {
        guard runningCount > 0 else {
            Logger.warning("releaseSlot called with runningCount at 0", category: .ai)
            return
        }
        runningCount -= 1

        // Resume a waiting task if any
        if let (id, continuation) = continuations.first {
            continuations.removeValue(forKey: id)
            continuation.resume()
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
    ///   - context: The customization context
    ///   - llmFacade: The LLM facade for API calls
    ///   - modelId: The model ID to use
    ///   - preamble: The preamble to prepend to each task prompt
    ///   - toolConfig: Optional tool configuration for tool-enabled execution
    /// - Returns: Dictionary mapping task IDs to results
    func executeAll(
        tasks: [RevisionTask],
        context: ParallelExecutionContext,
        llmFacade: LLMFacade,
        modelId: String,
        preamble: String,
        toolConfig: ToolConfiguration? = nil
    ) async -> [UUID: Result<ProposedRevisionNode, Error>] {
        var results: [UUID: Result<ProposedRevisionNode, Error>] = [:]

        let stream = execute(
            tasks: tasks,
            context: context,
            llmFacade: llmFacade,
            modelId: modelId,
            preamble: preamble,
            toolConfig: toolConfig
        )

        for await taskResult in stream {
            results[taskResult.taskId] = taskResult.result
        }

        return results
    }
}
