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

struct GitAnalysisResult: Codable {
    let summary: String
    let languages: [CompleteAnalysisTool.LanguageSkill]
    let technologies: [String]
    let skills: [CompleteAnalysisTool.SkillAssessment]
    let developmentPatterns: CompleteAnalysisTool.DevelopmentPatterns?
    let highlights: [String]
    let evidenceFiles: [String]

    enum CodingKeys: String, CodingKey {
        case summary, languages, technologies, skills, highlights
        case developmentPatterns = "development_patterns"
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
    private let maxTurns = 30
    private let timeoutSeconds: TimeInterval = 300  // 5 minutes

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
                updateProgress("Turn \(turnCount): Thinking...")

                // Call LLM with tools
                let response = try await facade.executeWithTools(
                    messages: messages,
                    tools: tools,
                    toolChoice: .auto,
                    modelId: modelId,
                    temperature: 0.3
                )

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

                // Execute each tool call
                for toolCall in toolCalls {
                    let toolName = toolCall.function.name ?? "unknown"
                    await emitEvent(.gitAgentToolExecuting(toolName: toolName, turn: turnCount))
                    updateProgress("Executing: \(toolName)")

                    // Check for completion tool
                    if toolName == CompleteAnalysisTool.name {
                        let result = try parseCompleteAnalysis(arguments: toolCall.function.arguments)
                        status = .completed
                        await emitEvent(.gitAgentProgressUpdated(message: "Analysis complete!", turn: turnCount))
                        updateProgress("Analysis complete!")
                        return result
                    }

                    // Execute the tool
                    let toolResult = await executeTool(name: toolName, arguments: toolCall.function.arguments)

                    // Add tool result to messages
                    messages.append(buildToolResultMessage(
                        toolCallId: toolCall.id ?? UUID().uuidString,
                        result: toolResult
                    ))
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
        var properties: [String: JSONSchema]? = nil

        if let propsDict = dict["properties"] as? [String: [String: Any]] {
            var propSchemas: [String: JSONSchema] = [:]
            for (key, propSpec) in propsDict {
                let typeStr = propSpec["type"] as? String ?? "string"
                let desc = propSpec["description"] as? String

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

                propSchemas[key] = JSONSchema(
                    type: schemaType,
                    description: desc
                )
            }
            properties = propSchemas
        }

        let required = dict["required"] as? [String]
        let additionalProps = dict["additionalProperties"] as? Bool ?? false

        return JSONSchema(
            type: .object,
            properties: properties,
            required: required,
            additionalProperties: additionalProps
        )
    }

    // MARK: - Result Parsing

    private func parseCompleteAnalysis(arguments: String) throws -> GitAnalysisResult {
        guard let data = arguments.data(using: .utf8) else {
            throw GitAgentError.invalidToolCall("Could not parse arguments as UTF-8")
        }

        do {
            let params = try JSONDecoder().decode(CompleteAnalysisTool.Parameters.self, from: data)
            return GitAnalysisResult(
                summary: params.summary,
                languages: params.languages,
                technologies: params.technologies,
                skills: params.skills,
                developmentPatterns: params.developmentPatterns,
                highlights: params.highlights,
                evidenceFiles: params.evidenceFiles
            )
        } catch {
            throw GitAgentError.invalidToolCall("Failed to decode complete_analysis: \(error.localizedDescription)")
        }
    }

    // MARK: - Progress Updates

    private func updateProgress(_ message: String) {
        currentAction = message
        progress.append("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
        Logger.info("🤖 GitAgent: \(message)", category: .ai)
    }

    // MARK: - Event Emission

    private func emitEvent(_ event: OnboardingEvent) async {
        guard let eventBus = eventBus else { return }
        await eventBus.publish(event)
    }
}
