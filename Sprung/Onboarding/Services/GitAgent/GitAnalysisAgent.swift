//
//  GitAnalysisAgent.swift
//  Sprung
//
//  Multi-turn agent for analyzing git repositories.
//  Uses filesystem tools to explore codebases and generate skill assessments.
//

import Foundation
import Observation
import SwiftOpenAI
import SwiftyJSON

// MARK: - Agent Status

enum GitAgentStatus: Equatable {
    case idle
    case running
    case completed
    case failed(String)
}

// MARK: - Agent Error

enum GitAgentError: LocalizedError {
    case noLLMFacade
    case maxTurnsExceeded
    case agentDidNotComplete
    case invalidToolCall(String)
    case toolExecutionFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .noLLMFacade:
            return "LLM service is not available"
        case .maxTurnsExceeded:
            return "Agent exceeded maximum number of turns without completing"
        case .agentDidNotComplete:
            return "Agent stopped without calling complete_analysis"
        case .invalidToolCall(let msg):
            return "Invalid tool call: \(msg)"
        case .toolExecutionFailed(let msg):
            return "Tool execution failed: \(msg)"
        case .timeout:
            return "Agent timed out"
        }
    }
}

// MARK: - Analysis Result

/// Git repository analysis result containing skills and narrative cards.
struct GitAnalysisResult: Codable {
    let skills: [Skill]
    let narrativeCards: [KnowledgeCard]
    let repoName: String
    let analyzedAt: Date

    enum CodingKeys: String, CodingKey {
        case skills
        case narrativeCards = "narrative_cards"
        case repoName = "repo_name"
        case analyzedAt = "analyzed_at"
    }

    init(skills: [Skill] = [], narrativeCards: [KnowledgeCard] = [], repoName: String, analyzedAt: Date = Date()) {
        self.skills = skills
        self.narrativeCards = narrativeCards
        self.repoName = repoName
        self.analyzedAt = analyzedAt
    }
}

// MARK: - Git Analysis Agent

@Observable
@MainActor
class GitAnalysisAgent {
    // Configuration
    private let repoPath: URL
    private let authorFilter: String?
    private let modelId: String
    private weak var facade: LLMFacade?
    private var eventBus: EventCoordinator?

    // Agent tracking
    private let agentId: String?
    private let tracker: AgentActivityTracker?

    // State
    private(set) var status: GitAgentStatus = .idle
    private(set) var currentAction: String = ""
    private(set) var progress: [String] = []
    private(set) var turnCount: Int = 0

    // Limits
    private let maxTurns = 50
    private let timeoutSeconds: TimeInterval = 600  // 10 minutes

    // Conversation state
    private var messages: [ChatCompletionParameters.Message] = []

    // Tools (built once at init)
    private var tools: [ChatCompletionParameters.Tool]

    init(
        repoPath: URL,
        authorFilter: String? = nil,
        modelId: String,
        facade: LLMFacade,
        eventBus: EventCoordinator? = nil,
        agentId: String? = nil,
        tracker: AgentActivityTracker? = nil
    ) {
        self.repoPath = repoPath
        self.authorFilter = authorFilter
        self.modelId = modelId
        self.facade = facade
        self.eventBus = eventBus
        self.agentId = agentId
        self.tracker = tracker
        self.tools = Self.buildTools()
    }

    // MARK: - Public API

    /// Run the agent to analyze the repository
    func run() async throws -> GitAnalysisResult {
        guard let facade = facade else {
            throw GitAgentError.noLLMFacade
        }

        status = .running
        turnCount = 0
        messages = []
        progress = []

        // Initialize conversation with system prompt and initial context
        messages.append(systemMessage())
        messages.append(initialUserMessage())

        let startTime = Date()

        do {
            while turnCount < maxTurns {
                // Check timeout
                if Date().timeIntervalSince(startTime) > timeoutSeconds {
                    throw GitAgentError.timeout
                }

                turnCount += 1
                await emitEvent(.gitAgentTurnStarted(turn: turnCount, maxTurns: maxTurns))
                await updateProgress("(Turn \(turnCount)) Calling LLM...")

                // Add turn marker to transcript
                if let agentId = agentId {
                    tracker?.appendTranscript(
                        agentId: agentId,
                        entryType: .turn,
                        content: "Turn \(turnCount) of \(maxTurns)",
                        details: nil
                    )
                }

                // Call LLM with tools
                let response = try await facade.executeWithTools(
                    messages: messages,
                    tools: tools,
                    toolChoice: .auto,
                    modelId: modelId,
                    temperature: 0.3
                )

                // Emit token usage event if available
                if let usage = response.usage {
                    let inputTokens = usage.promptTokens ?? 0
                    let outputTokens = usage.completionTokens ?? 0
                    let cachedTokens = usage.promptTokensDetails?.cachedTokens ?? 0

                    await emitEvent(.llmTokenUsageReceived(
                        modelId: modelId,
                        inputTokens: inputTokens,
                        outputTokens: outputTokens,
                        cachedTokens: cachedTokens,
                        reasoningTokens: 0,  // Chat API doesn't have reasoning tokens
                        source: .gitAgent
                    ))

                    // Update agent's token tracking
                    if let agentId = agentId {
                        tracker?.addTokenUsage(
                            agentId: agentId,
                            input: inputTokens,
                            output: outputTokens,
                            cached: cachedTokens
                        )
                    }
                }

                // Process response
                guard let choice = response.choices?.first,
                      let message = choice.message else {
                    throw GitAgentError.agentDidNotComplete
                }

                // Add assistant message to history
                messages.append(buildAssistantMessage(from: message))

                // Check finish reason
                let finishReason: String
                switch choice.finishReason {
                case .int(let val):
                    finishReason = String(val)
                case .string(let val):
                    finishReason = val
                case .none:
                    finishReason = ""
                }

                // If model returned text without tool calls, it might be done
                if finishReason == "stop" && (message.toolCalls == nil || message.toolCalls!.isEmpty) {
                    throw GitAgentError.agentDidNotComplete
                }

                // Process tool calls
                guard let toolCalls = message.toolCalls, !toolCalls.isEmpty else {
                    // No tool calls but also didn't finish properly
                    throw GitAgentError.agentDidNotComplete
                }

                // Check for completion tool first (terminates the agent loop)
                if let completionCall = toolCalls.first(where: { $0.function.name == CompleteAnalysisTool.name }) {
                    do {
                        let result = try parseCompleteAnalysis(arguments: completionCall.function.arguments)
                        status = .completed
                        await emitEvent(.gitAgentProgressUpdated(message: "Analysis complete!", turn: turnCount))
                        await updateProgress("Analysis complete!")
                        return result
                    } catch {
                        // Send detailed error back to LLM so it can retry with corrected JSON
                        let errorMessage = buildParsingErrorMessage(arguments: completionCall.function.arguments, error: error)
                        Logger.warning("⚠️ GitAgent: complete_analysis parsing failed, asking LLM to retry: \(error.localizedDescription)", category: .ai)
                        messages.append(buildToolResultMessage(
                            toolCallId: completionCall.id ?? UUID().uuidString,
                            result: errorMessage
                        ))
                        continue
                    }
                }

                // Filter to non-completion tool calls for parallel execution
                let executableCalls = toolCalls.filter { $0.function.name != CompleteAnalysisTool.name }

                // Log parallel execution
                let toolNames = executableCalls.map { $0.function.name ?? "unknown" }
                await updateProgress("(Turn \(turnCount)) Running: \(toolNames.joined(separator: ", "))")
                if executableCalls.count > 1 {
                    Logger.info("🚀 GitAgent: Executing \(executableCalls.count) tools in parallel", category: .ai)
                }

                // Execute tool calls concurrently
                let results = await withTaskGroup(of: (String, String, String).self, returning: [(String, String, String)].self) { group in
                    for toolCall in executableCalls {
                        let toolId = toolCall.id ?? UUID().uuidString
                        let toolName = toolCall.function.name ?? "unknown"
                        let arguments = toolCall.function.arguments

                        group.addTask { [self] in
                            await self.emitEvent(.gitAgentToolExecuting(toolName: toolName, turn: self.turnCount))
                            let result = await self.executeTool(name: toolName, arguments: arguments)
                            return (toolId, toolName, result)
                        }
                    }

                    var collected: [(String, String, String)] = []
                    for await result in group {
                        collected.append(result)
                    }
                    return collected
                }

                // Add all tool results to messages (order doesn't matter for tool responses)
                await updateProgress("(Turn \(turnCount)) Processing results...")
                for (toolId, toolName, result) in results {
                    let toolDetail = extractToolDetail(name: toolName, arguments: executableCalls.first { $0.id == toolId }?.function.arguments ?? "")
                    messages.append(buildToolResultMessage(toolCallId: toolId, result: result))

                    // Add tool call to transcript
                    if let agentId = agentId {
                        let displayName = toolDisplayName(toolName)
                        let content = toolDetail.isEmpty ? displayName : "\(displayName): \(toolDetail)"
                        tracker?.appendTranscript(
                            agentId: agentId,
                            entryType: .tool,
                            content: content,
                            details: nil
                        )
                    }
                }
            }

            // Max turns reached - force completion
            Logger.warning("⚠️ GitAgent: Max turns (\(maxTurns)) reached, forcing completion...", category: .ai)
            await updateProgress("(Turn \(turnCount + 1)) Forcing completion...")

            if let forcedResult = try await forceCompletion(facade: facade) {
                status = .completed
                return forcedResult
            }

            throw GitAgentError.maxTurnsExceeded

        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Forced Completion

    /// Forces the agent to call complete_analysis when max turns is reached.
    /// Adds a strong system message and makes one final LLM call.
    private func forceCompletion(facade: LLMFacade) async throws -> GitAnalysisResult? {
        // Add forceful message to conversation
        let forceMessage = ChatCompletionParameters.Message(
            role: .system,
            content: .text("""
                CRITICAL: You have reached the maximum number of analysis turns.
                You MUST call the complete_analysis tool NOW with your findings so far.
                Summarize what you've discovered and output the card inventory.
                Do NOT call any other tools - only call complete_analysis immediately.
                """)
        )
        messages.append(forceMessage)

        // Make one final call with auto tool choice (so it can call complete_analysis)
        let response = try await facade.executeWithTools(
            messages: messages,
            tools: tools,
            toolChoice: .auto,
            modelId: modelId,
            temperature: 0.2  // Lower temperature for more focused output
        )

        // Track token usage for this forced call
        if let usage = response.usage {
            let inputTokens = usage.promptTokens ?? 0
            let outputTokens = usage.completionTokens ?? 0
            let cachedTokens = usage.promptTokensDetails?.cachedTokens ?? 0

            if let agentId = agentId {
                tracker?.addTokenUsage(
                    agentId: agentId,
                    input: inputTokens,
                    output: outputTokens,
                    cached: cachedTokens
                )
            }
        }

        guard let choice = response.choices?.first,
              let message = choice.message,
              let toolCalls = message.toolCalls,
              let completionCall = toolCalls.first(where: { $0.function.name == CompleteAnalysisTool.name }) else {
            Logger.error("❌ GitAgent: Forced completion failed - no complete_analysis call received", category: .ai)
            return nil
        }

        do {
            let result = try parseCompleteAnalysis(arguments: completionCall.function.arguments)
            await emitEvent(.gitAgentProgressUpdated(message: "Analysis complete (forced)!", turn: turnCount + 1))
            await updateProgress("Analysis complete (forced)!")
            Logger.info("✅ GitAgent: Forced completion succeeded", category: .ai)
            return result
        } catch {
            Logger.error("❌ GitAgent: Forced completion parsing failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, arguments: String) async -> String {
        do {
            let argsData = arguments.data(using: .utf8) ?? Data()

            switch name {
            case ReadFileTool.name:
                let params = try JSONDecoder().decode(ReadFileTool.Parameters.self, from: argsData)
                let result = try ReadFileTool.execute(parameters: params, repoRoot: repoPath)
                return formatToolResult(result)

            case ListDirectoryTool.name:
                let params = try JSONDecoder().decode(ListDirectoryTool.Parameters.self, from: argsData)
                let result = try ListDirectoryTool.execute(parameters: params, repoRoot: repoPath)
                return result.formattedTree

            case GlobSearchTool.name:
                let params = try JSONDecoder().decode(GlobSearchTool.Parameters.self, from: argsData)
                let result = try GlobSearchTool.execute(parameters: params, repoRoot: repoPath)
                return formatGlobResult(result)

            case GrepSearchTool.name:
                let params = try JSONDecoder().decode(GrepSearchTool.Parameters.self, from: argsData)
                let result = try GrepSearchTool.execute(parameters: params, repoRoot: repoPath)
                return result.formatted

            default:
                return "Unknown tool: \(name)"
            }
        } catch {
            Logger.error("❌ Tool execution error (\(name)): \(error.localizedDescription)", category: .ai)
            return "Error: \(error.localizedDescription)"
        }
    }

    private func formatToolResult(_ result: ReadFileTool.Result) -> String {
        var output = "File content (lines \(result.startLine)-\(result.endLine) of \(result.totalLines)):\n"
        output += result.content
        if result.hasMore {
            output += "\n\n[Note: File has more content. Use offset=\(result.endLine + 1) to read more.]"
        }
        return output
    }

    private func formatGlobResult(_ result: GlobSearchTool.Result) -> String {
        var lines: [String] = ["Found \(result.totalMatches) files matching pattern:"]
        for file in result.files {
            let sizeStr = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
            lines.append("  \(file.relativePath) (\(sizeStr))")
        }
        if result.truncated {
            lines.append("  ... and \(result.totalMatches - result.files.count) more")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Message Building

    private func systemMessage() -> ChatCompletionParameters.Message {
        let prompt = GitAgentPrompts.systemPrompt(authorFilter: authorFilter)
        return ChatCompletionParameters.Message(
            role: .system,
            content: .text(prompt)
        )
    }

    private func initialUserMessage() -> ChatCompletionParameters.Message {
        let repoName = repoPath.lastPathComponent
        let prompt = """
        Please analyze the git repository at: \(repoPath.path)
        Repository name: \(repoName)

        Start by exploring the directory structure to understand the project layout, then examine key files to assess the developer's skills.
        """
        return ChatCompletionParameters.Message(
            role: .user,
            content: .text(prompt)
        )
    }

    private func buildAssistantMessage(from message: ChatCompletionObject.ChatChoice.ChatMessage) -> ChatCompletionParameters.Message {
        // Build content
        let content: ChatCompletionParameters.Message.ContentType
        if let text = message.content {
            content = .text(text)
        } else {
            content = .text("")
        }

        // Convert tool calls from response type to parameter type
        let convertedToolCalls: [SwiftOpenAI.ToolCall]? = message.toolCalls

        return ChatCompletionParameters.Message(
            role: .assistant,
            content: content,
            toolCalls: convertedToolCalls
        )
    }

    private func buildToolResultMessage(toolCallId: String, result: String) -> ChatCompletionParameters.Message {
        return ChatCompletionParameters.Message(
            role: .tool,
            content: .text(result),
            toolCallID: toolCallId
        )
    }

    // MARK: - Tool Definitions

    private static func buildTools() -> [ChatCompletionParameters.Tool] {
        [
            buildTool(ReadFileTool.self),
            buildTool(ListDirectoryTool.self),
            buildTool(GlobSearchTool.self),
            buildTool(GrepSearchTool.self),
            buildTool(CompleteAnalysisTool.self)
        ]
    }

    private static func buildTool<T: AgentTool>(_ tool: T.Type) -> ChatCompletionParameters.Tool {
        let schemaDict = tool.parametersSchema
        let schema = AgentSchemaUtilities.buildJSONSchema(from: schemaDict)

        let function = ChatCompletionParameters.ChatFunction(
            name: tool.name,
            strict: false,
            description: tool.description,
            parameters: schema
        )

        return ChatCompletionParameters.Tool(function: function)
    }

    // MARK: - Result Parsing

    private func buildParsingErrorMessage(arguments _: String, error: Error) -> String {
        // Extract specific decoding error details if available
        var specificError = error.localizedDescription
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .keyNotFound(let key, let context):
                specificError = "Missing required field '\(key.stringValue)' at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .typeMismatch(let type, let context):
                specificError = "Type mismatch for '\(context.codingPath.map(\.stringValue).joined(separator: "."))': expected \(type)"
            case .valueNotFound(let type, let context):
                specificError = "Missing value for '\(context.codingPath.map(\.stringValue).joined(separator: "."))': expected \(type)"
            case .dataCorrupted(let context):
                specificError = "Data corrupted at '\(context.codingPath.map(\.stringValue).joined(separator: "."))': \(context.debugDescription)"
            @unknown default:
                break
            }
        }

        return """
        ERROR: Failed to parse complete_analysis arguments.

        \(specificError)

        Your JSON must match this EXACT structure:
        {
          "summary": "string (required) - 2-3 sentence overview",
          "languages": [  // required array
            {
              "name": "string (required)",
              "proficiency": "string (required) - one of: beginner, intermediate, advanced, expert",
              "evidence": "string (required) - specific files demonstrating this"
            }
          ],
          "technologies": ["string"],  // required array of strings
          "skills": [  // required array
            {
              "skill": "string (required)",
              "evidence": "string (required)"
            }
          ],
          "development_patterns": {  // optional object
            "code_quality": "string (optional)",
            "testing_practices": "string (optional)",
            "documentation_quality": "string (optional)",
            "architecture_style": "string (optional)"
          },
          "highlights": ["string"],  // required array of strings
          "evidence_files": ["string"]  // required array of file paths examined
        }

        Please retry with corrected JSON.
        """
    }

    private func parseCompleteAnalysis(arguments: String) throws -> GitAnalysisResult {
        guard let data = arguments.data(using: .utf8) else {
            throw GitAgentError.invalidToolCall("Could not parse arguments as UTF-8")
        }

        do {
            let params = try JSONDecoder().decode(CompleteAnalysisTool.Parameters.self, from: data)
            let repoName = repoPath.lastPathComponent
            let docId = repoName

            var skills: [Skill] = []
            var narrativeCards: [KnowledgeCard] = []

            for card in params.cards {
                if card.cardType == "skill" {
                    // Convert skill cards to Skill objects
                    let evidence = card.evidenceLocations.map { location in
                        SkillEvidence(
                            documentId: docId,
                            location: location,
                            context: card.extractionNotes ?? "",
                            strength: EvidenceStrength(rawValue: card.evidenceStrength) ?? .supporting
                        )
                    }

                    let skill = Skill(
                        canonical: card.proposedTitle,
                        atsVariants: card.technologies,
                        category: .tools,  // Git analysis primarily finds tools/frameworks
                        proficiency: .proficient,  // Default to proficient for demonstrated skills
                        evidence: evidence
                    )
                    skills.append(skill)
                } else {
                    // Convert other card types to KnowledgeCard
                    let cardType: CardType = {
                        switch card.cardType {
                        case "project": return .project
                        case "achievement": return .achievement
                        case "education": return .education
                        case "employment": return .employment
                        default: return .project
                        }
                    }()

                    // Convert evidence locations to EvidenceAnchor
                    let evidenceAnchors = card.evidenceLocations.map { location in
                        EvidenceAnchor(
                            documentId: docId,
                            location: location,
                            verbatimExcerpt: nil
                        )
                    }

                    // Build narrative from key facts and outcomes
                    var narrativeParts: [String] = []
                    if let notes = card.extractionNotes, !notes.isEmpty {
                        narrativeParts.append(notes)
                    }
                    if !card.keyFacts.isEmpty {
                        narrativeParts.append("\n## Key Points\n" + card.keyFacts.joined(separator: "\n• "))
                    }
                    if !card.quantifiedOutcomes.isEmpty {
                        narrativeParts.append("\n## Outcomes\n" + card.quantifiedOutcomes.joined(separator: "\n• "))
                    }

                    let narrativeCard = KnowledgeCard(
                        title: card.proposedTitle,
                        narrative: narrativeParts.joined(separator: "\n"),
                        cardType: cardType,
                        dateRange: card.dateRange,
                        organization: repoName,
                        evidenceAnchors: evidenceAnchors,
                        extractable: ExtractableMetadata(
                            domains: card.technologies.prefix(5).map { String($0) },
                            scale: card.quantifiedOutcomes,
                            keywords: card.keyFacts.prefix(3).map { String($0) }
                        )
                    )
                    narrativeCards.append(narrativeCard)
                }
            }

            return GitAnalysisResult(
                skills: skills,
                narrativeCards: narrativeCards,
                repoName: repoName,
                analyzedAt: Date()
            )
        } catch {
            throw GitAgentError.invalidToolCall("Failed to decode complete_analysis: \(error.localizedDescription)")
        }
    }

    // MARK: - Progress Updates

    private func updateProgress(_ message: String) async {
        currentAction = message
        progress.append("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
        Logger.info("🤖 GitAgent: \(message)", category: .ai)
        // Update agent-specific status message in tracker (shown in BackgroundAgentStatusBar)
        // Note: We only emit extractionStateChanged if there's no tracker, to avoid duplicate status displays
        if let agentId = agentId {
            tracker?.updateStatusMessage(agentId: agentId, message: message)
        } else {
            // Fallback for agents not using the tracker - emit extraction state
            await emitEvent(.extractionStateChanged(true, statusMessage: "Git analysis: \(message)"))
        }
    }

    /// Extract a human-readable detail from tool arguments for logging
    private func extractToolDetail(name: String, arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }

        switch name {
        case ReadFileTool.name:
            if let path = json["path"] as? String {
                // Show just the filename or last path component
                let url = URL(fileURLWithPath: path)
                return url.lastPathComponent
            }
        case ListDirectoryTool.name:
            if let path = json["path"] as? String {
                let url = URL(fileURLWithPath: path)
                let depth = json["depth"] as? Int ?? 1
                return "\(url.lastPathComponent)/ (depth: \(depth))"
            }
        case GlobSearchTool.name:
            if let pattern = json["pattern"] as? String {
                return "pattern: \(pattern)"
            }
        case GrepSearchTool.name:
            if let pattern = json["pattern"] as? String {
                let glob = json["glob"] as? String
                if let glob = glob {
                    return "'\(pattern)' in \(glob)"
                }
                return "'\(pattern)'"
            }
        case CompleteAnalysisTool.name:
            return "submitting analysis"
        default:
            break
        }

        return ""
    }

    /// Convert tool name to human-readable display name
    private func toolDisplayName(_ name: String) -> String {
        switch name {
        case ReadFileTool.name: return "Read file"
        case ListDirectoryTool.name: return "List directory"
        case GlobSearchTool.name: return "Glob search"
        case GrepSearchTool.name: return "Grep search"
        case CompleteAnalysisTool.name: return "Complete analysis"
        default: return name
        }
    }

    // MARK: - Event Emission

    private func emitEvent(_ event: OnboardingEvent) async {
        guard let eventBus = eventBus else { return }
        await eventBus.publish(event)
    }
}
