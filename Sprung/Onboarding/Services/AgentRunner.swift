//
//  AgentRunner.swift
//  Sprung
//
//  Isolated agent execution loop for sub-agents (KC agents, etc.).
//  Each AgentRunner has its own conversation thread, tool executor, and response ID chain.
//  Based on GitAnalysisAgent pattern but generalized for any sub-agent type.
//
//  CRITICAL: Sub-agents are completely isolated from the main coordinator:
//  - Own responseId chain (never touches main's)
//  - Own message history (built locally)
//  - Own tool executor (limited tool set)
//  - Does NOT emit events to main EventCoordinator
//  - Does NOT call UI tools
//  - Does NOT write directly to ArtifactRepository
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

// MARK: - Agent Configuration

/// Configuration for an agent run
struct AgentConfiguration {
    let agentId: String
    let agentType: AgentType
    let name: String
    let modelId: String
    let systemPrompt: String
    let initialUserMessage: String
    let maxTurns: Int
    let timeoutSeconds: TimeInterval
    let temperature: Double

    init(
        agentId: String = UUID().uuidString,
        agentType: AgentType,
        name: String,
        modelId: String,
        systemPrompt: String,
        initialUserMessage: String,
        maxTurns: Int = 30,
        timeoutSeconds: TimeInterval = 300,
        temperature: Double = 0.3
    ) {
        self.agentId = agentId
        self.agentType = agentType
        self.name = name
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.initialUserMessage = initialUserMessage
        self.maxTurns = maxTurns
        self.timeoutSeconds = timeoutSeconds
        self.temperature = temperature
    }
}

// MARK: - Agent Output

/// Result returned by an agent when it completes
struct AgentOutput {
    let agentId: String
    let success: Bool
    let result: JSON?
    let error: String?
    let turnCount: Int
    let duration: TimeInterval
}

// MARK: - Agent Runner Errors

enum AgentRunnerError: LocalizedError {
    case noLLMFacade
    case maxTurnsExceeded(Int)
    case timeout(TimeInterval)
    case cancelled
    case noCompletionTool
    case invalidOutput(String)
    case toolExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noLLMFacade:
            return "LLM service is not available"
        case .maxTurnsExceeded(let turns):
            return "Agent exceeded maximum turns (\(turns)) without completing"
        case .timeout(let seconds):
            return "Agent timed out after \(Int(seconds)) seconds"
        case .cancelled:
            return "Agent was cancelled"
        case .noCompletionTool:
            return "Agent did not call completion tool"
        case .invalidOutput(let msg):
            return "Invalid agent output: \(msg)"
        case .toolExecutionFailed(let msg):
            return "Tool execution failed: \(msg)"
        }
    }
}

// MARK: - Agent Runner

/// Isolated agent execution loop.
/// Each instance runs a single agent conversation to completion.
actor AgentRunner {
    // MARK: - Configuration

    private let config: AgentConfiguration
    private let toolExecutor: SubAgentToolExecutor
    private let tracker: AgentActivityTracker?

    // MARK: - LLM Access

    private weak var llmFacade: LLMFacade?
    private weak var eventBus: EventCoordinator?

    // MARK: - Conversation State

    private var messages: [ChatCompletionParameters.Message] = []
    private var turnCount: Int = 0
    private var isCompleted: Bool = false
    private var completionResult: JSON?

    // MARK: - Initialization

    init(
        config: AgentConfiguration,
        toolExecutor: SubAgentToolExecutor,
        llmFacade: LLMFacade?,
        eventBus: EventCoordinator? = nil,
        tracker: AgentActivityTracker? = nil
    ) {
        self.config = config
        self.toolExecutor = toolExecutor
        self.llmFacade = llmFacade
        self.eventBus = eventBus
        self.tracker = tracker
    }

    // MARK: - Public API

    /// Run the agent to completion
    /// - Returns: AgentOutput with the result or error
    func run() async throws -> AgentOutput {
        let startTime = Date()

        guard let facade = llmFacade else {
            throw AgentRunnerError.noLLMFacade
        }

        // Initialize conversation
        messages = [
            systemMessage(),
            initialUserMessage()
        ]

        await logTranscript(type: .system, content: "Agent started", details: config.systemPrompt)
        await logTranscript(type: .system, content: "Initial prompt", details: config.initialUserMessage)

        do {
            // Agent loop
            while turnCount < config.maxTurns && !isCompleted {
                // Check for cancellation
                try Task.checkCancellation()

                // Check timeout
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > config.timeoutSeconds {
                    throw AgentRunnerError.timeout(config.timeoutSeconds)
                }

                turnCount += 1
                await logTranscript(type: .system, content: "Turn \(turnCount) started")

                // Call LLM with tools
                let tools = await toolExecutor.getToolSchemas()
                let response = try await facade.executeWithTools(
                    messages: messages,
                    tools: tools,
                    toolChoice: .auto,
                    modelId: config.modelId,
                    temperature: config.temperature
                )

                // Emit token usage event if available
                if let usage = response.usage {
                    await emitTokenUsage(
                        modelId: config.modelId,
                        inputTokens: usage.promptTokens ?? 0,
                        outputTokens: usage.completionTokens ?? 0,
                        cachedTokens: usage.promptTokensDetails?.cachedTokens ?? 0,
                        reasoningTokens: usage.completionTokensDetails?.reasoningTokens ?? 0
                    )
                }

                // Process response
                guard let choice = response.choices?.first,
                      let message = choice.message else {
                    throw AgentRunnerError.invalidOutput("No message in response")
                }

                // Add assistant message to history
                messages.append(buildAssistantMessage(from: message))

                // Log assistant content if any
                if let content = message.content, !content.isEmpty {
                    await logTranscript(type: .assistant, content: content)
                }

                // Check for tool calls
                guard let toolCalls = message.toolCalls, !toolCalls.isEmpty else {
                    // No tool calls and model stopped - check if it completed
                    if isCompleted {
                        break
                    }
                    throw AgentRunnerError.noCompletionTool
                }

                // Check for completion tool first
                if let completionCall = toolCalls.first(where: { $0.function.name == "return_result" }) {
                    let result = try parseCompletionResult(arguments: completionCall.function.arguments)
                    completionResult = result
                    isCompleted = true
                    await logTranscript(
                        type: .tool,
                        content: "return_result",
                        details: "Agent returned result successfully"
                    )
                    break
                }

                // Execute non-completion tools in parallel
                let executableCalls = toolCalls.filter { $0.function.name != "return_result" }

                let results = await withTaskGroup(of: (String, String, String).self) { group in
                    for toolCall in executableCalls {
                        let toolId = toolCall.id ?? UUID().uuidString
                        let toolName = toolCall.function.name ?? "unknown"
                        let arguments = toolCall.function.arguments

                        group.addTask { [self] in
                            await self.logTranscript(
                                type: .tool,
                                content: "Executing: \(toolName)",
                                details: arguments
                            )

                            let result = await self.toolExecutor.execute(
                                toolName: toolName,
                                arguments: arguments
                            )

                            return (toolId, toolName, result)
                        }
                    }

                    var collected: [(String, String, String)] = []
                    for await result in group {
                        collected.append(result)
                    }
                    return collected
                }

                // Add tool results to messages
                for (toolId, toolName, result) in results {
                    await logTranscript(
                        type: .toolResult,
                        content: "\(toolName) result",
                        details: String(result.prefix(500))
                    )
                    messages.append(buildToolResultMessage(toolCallId: toolId, result: result))
                }
            }

            // Check if we exceeded max turns
            if turnCount >= config.maxTurns && !isCompleted {
                throw AgentRunnerError.maxTurnsExceeded(config.maxTurns)
            }

            let duration = Date().timeIntervalSince(startTime)
            await logTranscript(
                type: .system,
                content: "Agent completed successfully",
                details: "Duration: \(String(format: "%.1f", duration))s, Turns: \(turnCount)"
            )

            return AgentOutput(
                agentId: config.agentId,
                success: true,
                result: completionResult,
                error: nil,
                turnCount: turnCount,
                duration: duration
            )

        } catch is CancellationError {
            let duration = Date().timeIntervalSince(startTime)
            await logTranscript(type: .error, content: "Agent cancelled", details: "Duration: \(String(format: "%.1f", duration))s")
            throw AgentRunnerError.cancelled
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            await logTranscript(type: .error, content: "Agent failed", details: "\(error.localizedDescription) (Duration: \(String(format: "%.1f", duration))s)")
            throw error
        }
    }

    // MARK: - Message Building

    private func systemMessage() -> ChatCompletionParameters.Message {
        ChatCompletionParameters.Message(
            role: .system,
            content: .text(config.systemPrompt)
        )
    }

    private func initialUserMessage() -> ChatCompletionParameters.Message {
        ChatCompletionParameters.Message(
            role: .user,
            content: .text(config.initialUserMessage)
        )
    }

    private func buildAssistantMessage(from message: ChatCompletionObject.ChatChoice.ChatMessage) -> ChatCompletionParameters.Message {
        let content: ChatCompletionParameters.Message.ContentType
        if let text = message.content {
            content = .text(text)
        } else {
            content = .text("")
        }

        return ChatCompletionParameters.Message(
            role: .assistant,
            content: content,
            toolCalls: message.toolCalls
        )
    }

    private func buildToolResultMessage(toolCallId: String, result: String) -> ChatCompletionParameters.Message {
        ChatCompletionParameters.Message(
            role: .tool,
            content: .text(result),
            toolCallID: toolCallId
        )
    }

    // MARK: - Result Parsing

    private func parseCompletionResult(arguments: String) throws -> JSON {
        guard let data = arguments.data(using: .utf8) else {
            throw AgentRunnerError.invalidOutput("Could not parse arguments as UTF-8")
        }

        do {
            return try JSON(data: data)
        } catch {
            throw AgentRunnerError.invalidOutput("Invalid JSON: \(error.localizedDescription)")
        }
    }

    // MARK: - Transcript Logging

    private func logTranscript(
        type: AgentTranscriptEntry.EntryType,
        content: String,
        details: String? = nil
    ) async {
        guard let tracker = tracker else { return }

        await MainActor.run {
            tracker.appendTranscript(
                agentId: config.agentId,
                entryType: type,
                content: content,
                details: details
            )
        }
    }

    // MARK: - Event Emission

    private func emitTokenUsage(
        modelId: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedTokens: Int,
        reasoningTokens: Int
    ) async {
        guard let eventBus = eventBus else { return }

        let source: UsageSource = (config.agentType == .knowledgeCard) ? .kcAgent : .mainCoordinator
        await eventBus.publish(.llmTokenUsageReceived(
            modelId: modelId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedTokens: cachedTokens,
            reasoningTokens: reasoningTokens,
            source: source
        ))

        // Update agent's token tracking
        await MainActor.run {
            tracker?.addTokenUsage(
                agentId: config.agentId,
                input: inputTokens,
                output: outputTokens,
                cached: cachedTokens
            )
        }
    }
}

// MARK: - Convenience Factory

extension AgentRunner {
    /// Create a runner for a knowledge card generation agent
    static func forKnowledgeCard(
        agentId: String = UUID().uuidString,
        cardTitle: String,
        systemPrompt: String,
        initialPrompt: String,
        modelId: String,
        toolExecutor: SubAgentToolExecutor,
        llmFacade: LLMFacade?,
        eventBus: EventCoordinator? = nil,
        tracker: AgentActivityTracker?
    ) -> AgentRunner {
        let config = AgentConfiguration(
            agentId: agentId,
            agentType: .knowledgeCard,
            name: cardTitle,
            modelId: modelId,
            systemPrompt: systemPrompt,
            initialUserMessage: initialPrompt,
            maxTurns: 30,
            timeoutSeconds: 300,
            temperature: 0.3
        )

        return AgentRunner(
            config: config,
            toolExecutor: toolExecutor,
            llmFacade: llmFacade,
            eventBus: eventBus,
            tracker: tracker
        )
    }
}
