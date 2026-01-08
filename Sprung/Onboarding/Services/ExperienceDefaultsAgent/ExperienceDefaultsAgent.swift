//
//  ExperienceDefaultsAgent.swift
//  Sprung
//
//  Multi-turn agent for generating experience defaults from knowledge cards.
//  Uses filesystem tools to read evidence and write structured resume content.
//

import Foundation
import Observation
import SwiftOpenAI
import SwiftyJSON

// MARK: - Agent Status

enum ExperienceDefaultsAgentStatus: Equatable {
    case idle
    case running
    case completed
    case failed(String)
}

// MARK: - Agent Error

enum ExperienceDefaultsAgentError: LocalizedError {
    case noLLMFacade
    case maxTurnsExceeded
    case agentDidNotComplete
    case workspaceError(String)
    case outputNotGenerated
    case timeout

    var errorDescription: String? {
        switch self {
        case .noLLMFacade:
            return "LLM service is not available"
        case .maxTurnsExceeded:
            return "Agent exceeded maximum turns without completing"
        case .agentDidNotComplete:
            return "Agent stopped without calling complete_generation"
        case .workspaceError(let msg):
            return "Workspace error: \(msg)"
        case .outputNotGenerated:
            return "Agent did not generate experience_defaults.json"
        case .timeout:
            return "Agent timed out"
        }
    }
}

// MARK: - Generation Result

struct ExperienceDefaultsResult {
    let defaults: JSON
    let sectionsGenerated: [String]
    let summary: String
    let turnsUsed: Int
}

// MARK: - Experience Defaults Agent

@Observable
@MainActor
class ExperienceDefaultsAgent {
    // Configuration
    private let workspacePath: URL
    private let modelId: String
    private weak var facade: LLMFacade?

    // Agent tracking
    private let agentId: String?
    private let tracker: AgentActivityTracker?

    // State
    private(set) var status: ExperienceDefaultsAgentStatus = .idle
    private(set) var currentAction: String = ""
    private(set) var progress: [String] = []
    private(set) var turnCount: Int = 0

    // Limits
    private let maxTurns = 50
    private let timeoutSeconds: TimeInterval = 600  // 10 minutes
    private let ephemeralTurns = 5

    // Conversation state
    private var messages: [ChatCompletionParameters.Message] = []
    private var ephemeralMessages: [(index: Int, addedAtTurn: Int, toolCallId: String)] = []

    // Tools
    private var tools: [ChatCompletionParameters.Tool]

    init(
        workspacePath: URL,
        modelId: String,
        facade: LLMFacade,
        agentId: String? = nil,
        tracker: AgentActivityTracker? = nil
    ) {
        self.workspacePath = workspacePath
        self.modelId = modelId
        self.facade = facade
        self.agentId = agentId
        self.tracker = tracker
        self.tools = Self.buildTools()
    }

    // MARK: - Public API

    /// Run the agent to generate experience defaults
    func run() async throws -> ExperienceDefaultsResult {
        guard let facade = facade else {
            throw ExperienceDefaultsAgentError.noLLMFacade
        }

        status = .running
        turnCount = 0
        messages = []
        progress = []

        // Initialize conversation
        messages.append(systemMessage())
        messages.append(initialUserMessage())

        let startTime = Date()
        var generationSummary = ""

        do {
            while turnCount < maxTurns {
                // Check timeout
                if Date().timeIntervalSince(startTime) > timeoutSeconds {
                    throw ExperienceDefaultsAgentError.timeout
                }

                turnCount += 1
                await updateProgress("Turn \(turnCount): Calling LLM...")

                // Log turn to tracker
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

                // Track token usage
                if let usage = response.usage, let agentId = agentId {
                    let inputTokens = usage.promptTokens ?? 0
                    let outputTokens = usage.completionTokens ?? 0
                    let cachedTokens = usage.promptTokensDetails?.cachedTokens ?? 0
                    tracker?.addTokenUsage(
                        agentId: agentId,
                        input: inputTokens,
                        output: outputTokens,
                        cached: cachedTokens
                    )
                }

                // Process response
                guard let choice = response.choices?.first,
                      let message = choice.message else {
                    throw ExperienceDefaultsAgentError.agentDidNotComplete
                }

                // Add assistant message to history
                messages.append(buildAssistantMessage(from: message))

                // Check finish reason
                let finishReason: String
                switch choice.finishReason {
                case .int(let val): finishReason = String(val)
                case .string(let val): finishReason = val
                case .none: finishReason = ""
                }

                // If model returned text without tool calls, prompt to continue
                if finishReason == "stop" && (message.toolCalls == nil || message.toolCalls!.isEmpty) {
                    messages.append(ChatCompletionParameters.Message(
                        role: .user,
                        content: .text("Please continue generating content or call complete_generation if you're done.")
                    ))
                    continue
                }

                // Process tool calls
                guard let toolCalls = message.toolCalls, !toolCalls.isEmpty else {
                    continue
                }

                // Check for completion tool
                if let completionCall = toolCalls.first(where: { $0.function.name == "complete_generation" }) {
                    generationSummary = parseCompletionSummary(arguments: completionCall.function.arguments)
                    status = .completed
                    await updateProgress("Generation complete!")

                    // Read the generated output
                    let outputFile = workspacePath.appendingPathComponent("output/experience_defaults.json")
                    guard FileManager.default.fileExists(atPath: outputFile.path) else {
                        throw ExperienceDefaultsAgentError.outputNotGenerated
                    }

                    let data = try Data(contentsOf: outputFile)
                    let defaults = try JSON(data: data)

                    // Determine which sections were generated
                    let sectionsGenerated = defaults.dictionaryValue.keys.filter { key in
                        !defaults[key].isEmpty
                    }

                    return ExperienceDefaultsResult(
                        defaults: defaults,
                        sectionsGenerated: Array(sectionsGenerated),
                        summary: generationSummary,
                        turnsUsed: turnCount
                    )
                }

                // Prune old ephemeral messages
                pruneEphemeralMessages()

                // Execute tool calls
                for toolCall in toolCalls {
                    let toolId = toolCall.id ?? UUID().uuidString
                    let toolName = toolCall.function.name ?? "unknown"
                    let arguments = toolCall.function.arguments

                    await updateProgress("Turn \(turnCount): \(toolDisplayName(toolName))")

                    let result = await executeTool(name: toolName, arguments: arguments)
                    let messageIndex = messages.count
                    messages.append(buildToolResultMessage(toolCallId: toolId, result: result))

                    // Mark file reads as ephemeral
                    if toolName == ReadFileTool.name {
                        ephemeralMessages.append((index: messageIndex, addedAtTurn: turnCount, toolCallId: toolId))
                    }

                    // Log to transcript
                    if let agentId = agentId {
                        tracker?.appendTranscript(
                            agentId: agentId,
                            entryType: .tool,
                            content: toolDisplayName(toolName),
                            details: extractToolDetail(name: toolName, arguments: arguments)
                        )
                    }
                }
            }

            // Max turns reached
            throw ExperienceDefaultsAgentError.maxTurnsExceeded

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
                let result = try ReadFileTool.execute(parameters: params, repoRoot: workspacePath)
                return formatReadResult(result)

            case ListDirectoryTool.name:
                let params = try JSONDecoder().decode(ListDirectoryTool.Parameters.self, from: argsData)
                let result = try ListDirectoryTool.execute(parameters: params, repoRoot: workspacePath)
                return result.formattedTree

            case WriteFileTool.name:
                let params = try JSONDecoder().decode(WriteFileTool.Parameters.self, from: argsData)
                let result = try WriteFileTool.execute(parameters: params, repoRoot: workspacePath)
                return "Successfully wrote \(result.bytesWritten) bytes to \(result.path)"

            case "complete_generation":
                // This is handled specially above, but provide a response anyway
                return "Generation complete. Processing output..."

            default:
                return "Unknown tool: \(name)"
            }
        } catch {
            Logger.error("ExperienceDefaultsAgent tool error (\(name)): \(error.localizedDescription)", category: .ai)
            return "Error: \(error.localizedDescription)"
        }
    }

    private func formatReadResult(_ result: ReadFileTool.Result) -> String {
        var output = "File content (lines \(result.startLine)-\(result.endLine) of \(result.totalLines)):\n"
        output += result.content
        if result.hasMore {
            output += "\n\n[File has more content. Use offset=\(result.endLine + 1) to read more.]"
        }
        return output
    }

    // MARK: - Message Building

    private func systemMessage() -> ChatCompletionParameters.Message {
        return ChatCompletionParameters.Message(
            role: .system,
            content: .text(PromptLibrary.experienceDefaultsAgentSystem)
        )
    }

    private func initialUserMessage() -> ChatCompletionParameters.Message {
        let prompt = """
        Generate experience defaults for the candidate in this workspace.

        Workspace path: \(workspacePath.path)

        Start by reading OVERVIEW.md to understand the workspace structure and your task.
        Then read the config and timeline to understand what to generate.

        Call complete_generation when you've written output/experience_defaults.json.
        """
        return ChatCompletionParameters.Message(
            role: .user,
            content: .text(prompt)
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
            buildTool(WriteFileTool.self),
            buildCompleteGenerationTool()
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

    private static func buildCompleteGenerationTool() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: "Call when you have finished generating experience_defaults.json",
            properties: [
                "summary": JSONSchema(
                    type: .string,
                    description: "Brief summary of what was generated (sections, counts, any gaps)"
                )
            ],
            required: ["summary"]
        )

        let function = ChatCompletionParameters.ChatFunction(
            name: "complete_generation",
            strict: false,
            description: "Call when generation is complete and output/experience_defaults.json has been written",
            parameters: schema
        )

        return ChatCompletionParameters.Tool(function: function)
    }

    // MARK: - Result Parsing

    private func parseCompletionSummary(arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSON(data: data) else {
            return "Generation complete"
        }
        return json["summary"].stringValue
    }

    // MARK: - Ephemeral Pruning

    private func pruneEphemeralMessages() {
        let expiredTurn = turnCount - ephemeralTurns
        let toRemove = ephemeralMessages.filter { $0.addedAtTurn <= expiredTurn }

        for item in toRemove {
            guard item.index < messages.count else { continue }

            messages[item.index] = ChatCompletionParameters.Message(
                role: .tool,
                content: .text("[Content pruned - file was read \(turnCount - item.addedAtTurn) turns ago. Re-read if needed.]"),
                toolCallID: item.toolCallId
            )
        }

        ephemeralMessages.removeAll { $0.addedAtTurn <= expiredTurn }

        if !toRemove.isEmpty {
            Logger.debug("🗂️ Pruned \(toRemove.count) ephemeral messages", category: .ai)
        }
    }

    // MARK: - Helpers

    private func updateProgress(_ message: String) async {
        currentAction = message
        progress.append("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
        Logger.info("🗂️ ExperienceDefaultsAgent: \(message)", category: .ai)

        if let agentId = agentId {
            tracker?.updateStatusMessage(agentId: agentId, message: message)
        }
    }

    private func toolDisplayName(_ name: String) -> String {
        switch name {
        case ReadFileTool.name: return "Read file"
        case ListDirectoryTool.name: return "List directory"
        case WriteFileTool.name: return "Write file"
        case "complete_generation": return "Complete generation"
        default: return name
        }
    }

    private func extractToolDetail(name: String, arguments: String) -> String? {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch name {
        case ReadFileTool.name, WriteFileTool.name:
            return json["path"] as? String
        case ListDirectoryTool.name:
            return json["path"] as? String ?? "."
        case "complete_generation":
            return "Finished"
        default:
            return nil
        }
    }
}
