//
//  SubAgentToolExecutor.swift
//  Sprung
//
//  Minimal tool executor for isolated sub-agents (e.g., Git analysis agents).
//  Uses the same FileSystemTools as GitAnalysisAgent for unified access:
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
            strict: false,
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
        // Schema for individual facts extracted from artifacts
        let factSchema = JSONSchema(
            type: .object,
            description: "An extracted fact from the source artifacts",
            properties: [
                "category": JSONSchema(
                    type: .string,
                    description: "Fact category",
                    enum: ["responsibility", "achievement", "skill", "metric", "context", "collaboration"]
                ),
                "statement": JSONSchema(type: .string, description: "The extracted fact as a clear statement"),
                "confidence": JSONSchema(
                    type: .string,
                    description: "Confidence level",
                    enum: ["high", "medium", "low"]
                ),
                "source": JSONSchema(type: .string, description: "Artifact filename this fact came from")
            ],
            required: ["category", "statement", "confidence", "source"],
            additionalProperties: false
        )

        let resultSchema = JSONSchema(
            type: .object,
            description: "Knowledge card generation output - fact-based format",
            properties: [
                "card_type": JSONSchema(
                    type: .string,
                    description: "Card type/category",
                    enum: ["job", "skill", "education", "project", "employment", "achievement"]
                ),
                "title": JSONSchema(type: .string, description: "Card title (non-empty)"),
                "facts": JSONSchema(
                    type: .array,
                    description: "Array of extracted facts from the artifacts. Include ALL relevant facts (minimum 3).",
                    items: factSchema
                ),
                "suggested_bullets": JSONSchema(
                    type: .array,
                    description: "Resume bullet point templates derived from facts",
                    items: JSONSchema(type: .string)
                ),
                "technologies": JSONSchema(
                    type: .array,
                    description: "Technologies, tools, and skills mentioned",
                    items: JSONSchema(type: .string)
                ),
                "sources_used": JSONSchema(
                    type: .array,
                    description: "Artifact filenames used as evidence sources",
                    items: JSONSchema(type: .string)
                ),
                "date_range": JSONSchema(type: .string, description: "Date range (empty string if not applicable)"),
                "organization": JSONSchema(type: .string, description: "Organization name (empty string if not applicable)"),
                "location": JSONSchema(type: .string, description: "Location/remote (empty string if not applicable)")
            ],
            required: ["card_type", "title", "facts", "suggested_bullets", "technologies", "sources_used", "date_range", "organization", "location"],
            additionalProperties: false
        )

        let schema = JSONSchema(
            type: .object,
            description: """
                Return the completed result when you have finished your task.
                Call this tool when you have generated the complete output.
                The result JSON will be returned to the calling coordinator.

                For knowledge card agents, the result should include:
                - card_type: "job", "skill", "education", "project", "employment", or "achievement"
                - title: Title of the knowledge card
                - facts: Array of extracted facts with category, statement, confidence, and source
                - suggested_bullets: Resume bullet templates derived from facts
                - technologies: Tools, languages, frameworks mentioned
                - sources_used: Artifact filenames used as evidence
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
