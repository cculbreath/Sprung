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

/// Comprehensive git repository analysis result matching the complete_analysis tool schema
struct GitAnalysisResult: Codable {
    let repositorySummary: CompleteAnalysisTool.RepositorySummary
    let technicalSkills: [CompleteAnalysisTool.TechnicalSkill]
    let aiCollaborationProfile: CompleteAnalysisTool.AICollaborationProfile
    let architecturalCompetencies: [CompleteAnalysisTool.ArchitecturalCompetency]?
    let professionalAttributes: [CompleteAnalysisTool.ProfessionalAttribute]?
    let quantitativeMetrics: CompleteAnalysisTool.QuantitativeMetrics?
    let notableAchievements: [CompleteAnalysisTool.NotableAchievement]
    let keywordCloud: CompleteAnalysisTool.KeywordCloud
    let evidenceFiles: [String]

    enum CodingKeys: String, CodingKey {
        case repositorySummary = "repository_summary"
        case technicalSkills = "technical_skills"
        case aiCollaborationProfile = "ai_collaboration_profile"
        case architecturalCompetencies = "architectural_competencies"
        case professionalAttributes = "professional_attributes"
        case quantitativeMetrics = "quantitative_metrics"
        case notableAchievements = "notable_achievements"
        case keywordCloud = "keyword_cloud"
        case evidenceFiles = "evidence_files"
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
        eventBus: EventCoordinator? = nil
    ) {
        self.repoPath = repoPath
        self.authorFilter = authorFilter
        self.modelId = modelId
        self.facade = facade
        self.eventBus = eventBus
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
                await updateProgress("Turn \(turnCount): Thinking...")

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
                    await emitEvent(.llmTokenUsageReceived(
                        modelId: modelId,
                        inputTokens: usage.promptTokens ?? 0,
                        outputTokens: usage.completionTokens ?? 0,
                        cachedTokens: usage.promptTokensDetails?.cachedTokens ?? 0,
                        reasoningTokens: 0  // Chat API doesn't have reasoning tokens
                    ))
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
                if executableCalls.count > 1 {
                    await updateProgress("Executing \(executableCalls.count) tools in parallel: \(toolNames.joined(separator: ", "))")
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
                for (toolId, toolName, result) in results {
                    let toolDetail = extractToolDetail(name: toolName, arguments: executableCalls.first { $0.id == toolId }?.function.arguments ?? "")
                    let progressMessage = toolDetail.isEmpty ? "Completed: \(toolName)" : "Completed: \(toolName) - \(toolDetail)"
                    await updateProgress(progressMessage)
                    messages.append(buildToolResultMessage(toolCallId: toolId, result: result))
                }
            }

            throw GitAgentError.maxTurnsExceeded

        } catch {
            status = .failed(error.localizedDescription)
            throw error
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
        // Build JSONSchema from the tool's parameter schema
        let schemaDict = tool.parametersSchema
        let schema = buildJSONSchema(from: schemaDict)

        let function = ChatCompletionParameters.ChatFunction(
            name: tool.name,
            strict: false,
            description: tool.description,
            parameters: schema
        )

        return ChatCompletionParameters.Tool(function: function)
    }

    private static func buildJSONSchema(from dict: [String: Any]) -> JSONSchema {
        return buildJSONSchemaRecursive(from: dict)
    }

    private static func buildJSONSchemaRecursive(from dict: [String: Any]) -> JSONSchema {
        let typeStr = dict["type"] as? String ?? "object"
        let desc = dict["description"] as? String
        let enumValues = dict["enum"] as? [String]

        let schemaType: JSONSchemaType
        switch typeStr {
        case "string": schemaType = .string
        case "integer": schemaType = .integer
        case "number": schemaType = .number
        case "boolean": schemaType = .boolean
        case "array": schemaType = .array
        case "object": schemaType = .object
        default: schemaType = .string
        }

        // Handle properties for objects
        var properties: [String: JSONSchema]? = nil
        if let propsDict = dict["properties"] as? [String: [String: Any]] {
            var propSchemas: [String: JSONSchema] = [:]
            for (key, propSpec) in propsDict {
                propSchemas[key] = buildJSONSchemaRecursive(from: propSpec)
            }
            properties = propSchemas
        }

        // Handle items for arrays
        var items: JSONSchema? = nil
        if schemaType == .array, let itemsDict = dict["items"] as? [String: Any] {
            items = buildJSONSchemaRecursive(from: itemsDict)
        }

        let required = dict["required"] as? [String]
        let additionalProps = dict["additionalProperties"] as? Bool ?? false

        // JSONSchema init order: type, description, properties, items, required, additionalProperties, enum
        return JSONSchema(
            type: schemaType,
            description: desc,
            properties: properties,
            items: items,
            required: required,
            additionalProperties: additionalProps,
            enum: enumValues
        )
    }

    // MARK: - Result Parsing

    private func buildParsingErrorMessage(arguments: String, error: Error) -> String {
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
            return GitAnalysisResult(
                repositorySummary: params.repositorySummary,
                technicalSkills: params.technicalSkills,
                aiCollaborationProfile: params.aiCollaborationProfile,
                architecturalCompetencies: params.architecturalCompetencies,
                professionalAttributes: params.professionalAttributes,
                quantitativeMetrics: params.quantitativeMetrics,
                notableAchievements: params.notableAchievements,
                keywordCloud: params.keywordCloud,
                evidenceFiles: params.evidenceFiles
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
        // Update extraction status without blocking chat input
        await emitEvent(.extractionStateChanged(true, statusMessage: "Git analysis: \(message)"))
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

    // MARK: - Event Emission

    private func emitEvent(_ event: OnboardingEvent) async {
        guard let eventBus = eventBus else { return }
        await eventBus.publish(event)
    }
}
