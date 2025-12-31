//
//  AgentRunner.swift
//  Sprung
//
//  Isolated agent execution loop for sub-agents (e.g., Git analysis agents).
//  Each AgentRunner has its own conversation thread, tool executor, and response ID chain.
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
    let modelId: String
    let systemPrompt: String
    let initialUserMessage: String
    let maxTurns: Int
    let timeoutSeconds: TimeInterval
    let temperature: Double
    let reasoningEffort: String?

    init(
        agentId: String = UUID().uuidString,
        agentType: AgentType,
        modelId: String,
        systemPrompt: String,
        initialUserMessage: String,
        maxTurns: Int = 30,
        timeoutSeconds: TimeInterval = 300,
        temperature: Double = 0.3,
        reasoningEffort: String? = nil
    ) {
        self.agentId = agentId
        self.agentType = agentType
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.initialUserMessage = initialUserMessage
        self.maxTurns = maxTurns
        self.timeoutSeconds = timeoutSeconds
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
    }
}

// MARK: - Agent Output

/// Result returned by an agent when it completes
struct AgentOutput {
    let result: JSON?
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
    private var textOnlyRetries: Int = 0
    private let maxTextOnlyRetries: Int = 2
    private var invalidCompletionRetries: Int = 0
    private let maxInvalidCompletionRetries: Int = 2
    private var emptyResponseRetries: Int = 0
    private let maxEmptyResponseRetries: Int = 3

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
                await updateStatus("(Turn \(turnCount)) Calling LLM...")

                // Call LLM with tools
                let tools = await toolExecutor.getToolSchemas()
                let response = try await facade.executeWithTools(
                    messages: messages,
                    tools: tools,
                    toolChoice: .auto,
                    modelId: config.modelId,
                    temperature: config.temperature,
                    reasoningEffort: config.reasoningEffort
                )

                // Emit token usage event if available
                let outputTokens = response.usage?.completionTokens ?? 0
                if let usage = response.usage {
                    await emitTokenUsage(
                        modelId: config.modelId,
                        inputTokens: usage.promptTokens ?? 0,
                        outputTokens: outputTokens,
                        cachedTokens: usage.promptTokensDetails?.cachedTokens ?? 0,
                        reasoningTokens: usage.completionTokensDetails?.reasoningTokens ?? 0
                    )
                }

                // Detect empty API response (0 output tokens indicates API issue, not model choice)
                let hasContent = response.choices?.first?.message?.content?.isEmpty == false
                let hasToolCalls = response.choices?.first?.message?.toolCalls?.isEmpty == false
                let isEmptyResponse = outputTokens == 0 && !hasContent && !hasToolCalls

                if isEmptyResponse {
                    emptyResponseRetries += 1
                    await logTranscript(
                        type: .error,
                        content: "Empty API response (attempt \(emptyResponseRetries)/\(maxEmptyResponseRetries))",
                        details: "0 output tokens - likely rate limit or API overload"
                    )

                    if emptyResponseRetries >= maxEmptyResponseRetries {
                        throw AgentRunnerError.invalidOutput("API returned empty responses \(maxEmptyResponseRetries) times")
                    }

                    // Wait before retrying (exponential backoff: 1s, 2s, 4s)
                    let delay = pow(2.0, Double(emptyResponseRetries - 1))
                    try await Task.sleep(for: .seconds(delay))

                    // Don't increment turnCount for empty responses - retry the same turn
                    turnCount -= 1
                    continue
                }

                // Got a real response - reset empty response counter
                emptyResponseRetries = 0

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
                    // No tool calls - check if already completed
                    if isCompleted {
                        break
                    }

                    // Track consecutive text-only responses
                    textOnlyRetries += 1
                    await logTranscript(
                        type: .error,
                        content: "No tool call in response (attempt \(textOnlyRetries)/\(maxTextOnlyRetries))",
                        details: message.content ?? "(no content)"
                    )

                    if textOnlyRetries >= maxTextOnlyRetries {
                        throw AgentRunnerError.noCompletionTool
                    }

                    // Send reminder to use the return_result tool
                    let reminderMessage = """
                    You must call the `return_result` tool to submit your completed knowledge card.

                    Do not respond with text only - you MUST call `return_result` with a JSON object containing:
                    - card_type: one of job/skill/education/project/employment/achievement
                    - title: non-empty card title
                    - facts: array of extracted facts (minimum 3) with category, statement, confidence, source
                    - suggested_bullets: resume bullet templates
                    - technologies: tools and skills mentioned
                    - sources_used: artifact filenames used as evidence

                    Call `return_result` now with your completed card.
                    """
                    messages.append(buildUserMessage(content: reminderMessage))
                    await logTranscript(type: .system, content: "Sent return_result reminder")
                    continue
                }

                // Successfully got tool calls - reset retry counter
                textOnlyRetries = 0

                // Execute non-completion tools in parallel FIRST, then handle completion
                // This ensures we send tool results for ALL tool calls even when return_result is present
                // (OpenAI API requires results for every tool call in a batch)
                let executableCalls = toolCalls.filter { $0.function.name != "return_result" }
                let toolNames = executableCalls.compactMap { $0.function.name }.joined(separator: ", ")
                await updateStatus("(Turn \(turnCount)) Running: \(toolNames)")

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
                await updateStatus("(Turn \(turnCount)) Processing results...")
                for (toolId, toolName, result) in results {
                    await logTranscript(
                        type: .toolResult,
                        content: "\(toolName) result",
                        details: String(result.prefix(500))
                    )
                    messages.append(buildToolResultMessage(toolCallId: toolId, result: result))
                }

                // NOW check for completion tool (after all other tool results are added)
                // This ensures we send results for ALL tool calls before breaking the loop
                if let completionCall = toolCalls.first(where: { $0.function.name == "return_result" }) {
                    // Add tool result for return_result itself (required by API)
                    messages.append(buildToolResultMessage(
                        toolCallId: completionCall.id ?? UUID().uuidString,
                        result: "{\"status\": \"result_captured\"}"
                    ))

                    let result = try parseCompletionResult(arguments: completionCall.function.arguments)

                    if config.agentType == .knowledgeCard,
                       let errorMessage = knowledgeCardCompletionValidationError(result) {
                        invalidCompletionRetries += 1
                        await logTranscript(
                            type: .error,
                            content: "Invalid return_result payload (attempt \(invalidCompletionRetries)/\(maxInvalidCompletionRetries))",
                            details: errorMessage
                        )

                        if invalidCompletionRetries >= maxInvalidCompletionRetries {
                            throw AgentRunnerError.invalidOutput("Invalid return_result payload: \(errorMessage)")
                        }

                        let correctionMessage = """
                        Your last `return_result` payload was invalid:
                        \(errorMessage)

                        Fix the JSON and call `return_result` again. Requirements:
                        - result.card_type: one of job/skill/education/project/employment/achievement
                        - result.title: non-empty
                        - result.facts: array of extracted facts with category, statement, confidence, source
                        - result.suggested_bullets: array of resume bullet templates
                        - result.technologies: array of technologies/tools mentioned
                        - result.sources_used: artifact IDs used as evidence
                        """
                        messages.append(buildUserMessage(content: correctionMessage))
                        await logTranscript(type: .system, content: "Sent return_result correction request")
                        continue
                    }

                    completionResult = result
                    isCompleted = true
                    await logTranscript(
                        type: .tool,
                        content: "return_result",
                        details: "Agent returned result successfully"
                    )
                    break
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

            return AgentOutput(result: completionResult)

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

    private func buildUserMessage(content: String) -> ChatCompletionParameters.Message {
        ChatCompletionParameters.Message(
            role: .user,
            content: .text(content)
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

    private func knowledgeCardCompletionValidationError(_ payload: JSON) -> String? {
        let result = payload["result"]
        guard result != .null else {
            return "Missing required top-level key `result` (object)."
        }

        let cardType = result["card_type"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if cardType.isEmpty {
            return "Missing `result.card_type` (job/skill/education/project/employment)."
        }
        let validTypes = ["job", "skill", "education", "project", "employment", "achievement"]
        if !validTypes.contains(cardType) {
            return "Invalid `result.card_type` value '\(cardType)'."
        }

        let title = result["title"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return "Missing `result.title` (non-empty string)."
        }

        // Fact-based format validation
        let facts = result["facts"].arrayValue
        if facts.isEmpty {
            return "Missing `result.facts` (array of extracted facts with source attribution)."
        }
        if facts.count < 3 {
            return "`result.facts` has too few items (\(facts.count)). Extract all relevant facts from the artifacts."
        }

        let sourcesUsed = result["sources_used"].arrayValue
            .map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if sourcesUsed.isEmpty {
            return "No evidence sources provided. Include `result.sources_used` (artifact IDs used)."
        }

        return nil
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

    // MARK: - Status Updates

    private func updateStatus(_ message: String) async {
        guard let tracker = tracker else { return }

        await MainActor.run {
            tracker.updateStatusMessage(agentId: config.agentId, message: message)
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

        let source: UsageSource = (config.agentType == .knowledgeCard) ? .cardGeneration : .mainCoordinator
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
        // Read hard task reasoning effort from settings (used for KC generation)
        let reasoningEffort = UserDefaults.standard.string(forKey: "onboardingInterviewHardTaskReasoningEffort")
        Logger.info("🧠 KC Agent '\(cardTitle)' using reasoning effort: \(reasoningEffort ?? "default")", category: .ai)

        let config = AgentConfiguration(
            agentId: agentId,
            agentType: .knowledgeCard,
            modelId: modelId,
            systemPrompt: systemPrompt,
            initialUserMessage: initialPrompt,
            maxTurns: 30,
            timeoutSeconds: 300,
            temperature: 0.3,
            reasoningEffort: reasoningEffort
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
