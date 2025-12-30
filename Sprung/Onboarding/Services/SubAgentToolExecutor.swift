//
//  SubAgentToolExecutor.swift
//  Sprung
//
//  Minimal tool executor for isolated sub-agents (KC agents, etc.).
//  Uses the SAME FileSystemTools as GitAnalysisAgent for unified access:
//
//  FILESYSTEM TOOLS (same as Git agent):
//  - read_file: Read file content with line numbers
//  - list_directory: List directory contents with depth traversal
//  - glob_search: Find files matching glob patterns
//  - grep_search: Search file contents with regex
//
//  COMPLETION TOOL:
//  - return_result: Return completion result to AgentRunner
//
//  Artifacts must be exported to a temp directory before use.
//  Use OnboardingSessionStore.exportArtifactsToFilesystem() or exportArtifactsByIds().
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

// MARK: - Sub-Agent Tool Executor

/// Minimal tool executor for isolated sub-agents.
/// Takes a pre-exported filesystem directory and uses same tools as Git agent.
actor SubAgentToolExecutor {
    // MARK: - State

    private let repoRoot: URL

    // MARK: - Initialization

    /// Initialize with a pre-exported filesystem directory.
    /// The directory should contain artifact folders created by OnboardingSessionStore.exportArtifacts*.
    init(filesystemRoot: URL) {
        self.repoRoot = filesystemRoot
    }

    // MARK: - Public API

    /// Get tool schemas for LLM (same tools as Git agent + return_result)
    func getToolSchemas() -> [ChatCompletionParameters.Tool] {
        [
            buildTool(ReadFileTool.self),
            buildTool(ListDirectoryTool.self),
            buildTool(GlobSearchTool.self),
            buildTool(GrepSearchTool.self),
            buildReturnResultTool()
        ]
    }

    /// Execute a tool call
    /// - Returns: JSON string result
    func execute(toolName: String, arguments: String) async -> String {
        do {
            let argsData = arguments.data(using: .utf8) ?? Data()

            switch toolName {
            // Same tools as Git agent
            case ReadFileTool.name:
                let params = try JSONDecoder().decode(ReadFileTool.Parameters.self, from: argsData)
                let result = try ReadFileTool.execute(parameters: params, repoRoot: repoRoot)
                return formatReadResult(result)

            case ListDirectoryTool.name:
                let params = try JSONDecoder().decode(ListDirectoryTool.Parameters.self, from: argsData)
                let result = try ListDirectoryTool.execute(parameters: params, repoRoot: repoRoot)
                return result.formattedTree

            case GlobSearchTool.name:
                let params = try JSONDecoder().decode(GlobSearchTool.Parameters.self, from: argsData)
                let result = try GlobSearchTool.execute(parameters: params, repoRoot: repoRoot)
                return formatGlobResult(result)

            case GrepSearchTool.name:
                let params = try JSONDecoder().decode(GrepSearchTool.Parameters.self, from: argsData)
                let result = try GrepSearchTool.execute(parameters: params, repoRoot: repoRoot)
                return result.formatted

            case "return_result":
                // This is handled by AgentRunner, just return success
                return "{\"status\": \"result_captured\"}"

            default:
                return errorResult("Tool not available for sub-agents: \(toolName)")
            }
        } catch {
            Logger.error("❌ SubAgent tool execution error (\(toolName)): \(error.localizedDescription)", category: .ai)
            return errorResult(error.localizedDescription)
        }
    }

    // MARK: - Result Formatting

    private func formatReadResult(_ result: ReadFileTool.Result) -> String {
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

    private func errorResult(_ message: String) -> String {
        var result = JSON()
        result["status"].string = "error"
        result["error"].string = message
        return result.rawString() ?? "{\"status\": \"error\"}"
    }

    // MARK: - Tool Schema Building

    private func buildTool<T: AgentTool>(_ tool: T.Type) -> ChatCompletionParameters.Tool {
        let schemaDict = tool.parametersSchema
        let schema = buildJSONSchema(from: schemaDict)

        let function = ChatCompletionParameters.ChatFunction(
            name: tool.name,
            strict: true,
            description: tool.description,
            parameters: schema
        )

        return ChatCompletionParameters.Tool(function: function)
    }

    private func buildJSONSchema(from dict: [String: Any]) -> JSONSchema {
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

        var properties: [String: JSONSchema]? = nil
        if let propsDict = dict["properties"] as? [String: [String: Any]] {
            var propSchemas: [String: JSONSchema] = [:]
            for (key, propSpec) in propsDict {
                propSchemas[key] = buildJSONSchema(from: propSpec)
            }
            properties = propSchemas
        }

        var items: JSONSchema? = nil
        if schemaType == .array, let itemsDict = dict["items"] as? [String: Any] {
            items = buildJSONSchema(from: itemsDict)
        }

        let required = dict["required"] as? [String]
        let additionalProps = dict["additionalProperties"] as? Bool ?? false

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

    private func buildReturnResultTool() -> ChatCompletionParameters.Tool {
        let chatSourceSchema = JSONSchema(
            type: .object,
            description: "A source excerpt from the user conversation used as evidence",
            properties: [
                "excerpt": JSONSchema(type: .string, description: "Direct quote from the user"),
                "context": JSONSchema(type: .string, description: "Why this excerpt matters / what it supports")
            ],
            required: ["excerpt", "context"],
            additionalProperties: false
        )

        let resultSchema = JSONSchema(
            type: .object,
            description: "Knowledge card generation output",
            properties: [
                "card_type": JSONSchema(
                    type: .string,
                    description: "Card type/category",
                    enum: ["job", "skill", "education", "project"]
                ),
                "title": JSONSchema(type: .string, description: "Card title (non-empty)"),
                "prose": JSONSchema(
                    type: .string,
                    description: "Comprehensive narrative prose (500-2000+ words). Must be non-empty."
                ),
                "highlights": JSONSchema(type: .array, description: "Key achievements (bullets)", items: JSONSchema(type: .string)),
                "skills": JSONSchema(type: .array, description: "Skills demonstrated", items: JSONSchema(type: .string)),
                "metrics": JSONSchema(type: .array, description: "Quantitative results", items: JSONSchema(type: .string)),
                "sources": JSONSchema(
                    type: .array,
                    description: "File names used as evidence (prefer non-empty); include assigned files whenever possible.",
                    items: JSONSchema(type: .string)
                ),
                "chat_sources": JSONSchema(
                    type: .array,
                    description: "Conversation excerpts used as evidence (can be empty array)",
                    items: chatSourceSchema
                ),
                "time_period": JSONSchema(type: .string, description: "Date range (empty string if not applicable)"),
                "organization": JSONSchema(type: .string, description: "Organization name (empty string if not applicable)"),
                "location": JSONSchema(type: .string, description: "Location/remote (empty string if not applicable)")
            ],
            required: ["card_type", "title", "prose", "highlights", "skills", "metrics", "sources", "chat_sources", "time_period", "organization", "location"],
            additionalProperties: false
        )

        let schema = JSONSchema(
            type: .object,
            description: """
                Return the completed result when you have finished your task.
                Call this tool when you have generated the complete output.
                The result JSON will be returned to the calling coordinator.

                For knowledge card agents, the result should include:
                - card_type: "job" or "skill"
                - title: Title of the knowledge card
                - prose: Comprehensive narrative (500-2000+ words)
                - sources: Array of file names used
                - highlights: Key achievements or competencies
                - skills: Relevant skills demonstrated
                - metrics: Quantitative achievements if available
                """,
            properties: [
                "result": resultSchema
            ],
            required: ["result"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "return_result",
                strict: true,
                description: "Return completed result to the coordinator. Call when task is complete.",
                parameters: schema
            )
        )
    }
}

// MARK: - Errors

enum SubAgentToolError: LocalizedError {
    case invalidParameters(String)
    case notFound(String)
    case toolNotAvailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidParameters(let msg):
            return "Invalid parameters: \(msg)"
        case .notFound(let msg):
            return "Not found: \(msg)"
        case .toolNotAvailable(let name):
            return "Tool not available for sub-agents: \(name)"
        }
    }
}
