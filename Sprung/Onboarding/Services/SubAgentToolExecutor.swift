//
//  SubAgentToolExecutor.swift
//  Sprung
//
//  Minimal tool executor for isolated sub-agents (KC agents, etc.).
//  Provides a RESTRICTED tool set that avoids infrastructure conflicts:
//
//  ALLOWED (READ-ONLY):
//  - get_artifact: Read full artifact content from shared ArtifactRepository
//  - get_artifact_summary: Read artifact summary only
//  - return_result: Return completion result to AgentRunner (does NOT persist)
//
//  BLOCKED (would conflict with main coordinator):
//  - get_user_option: Requires UI, sets global waitingState
//  - get_user_upload: Requires UI, sets global waitingState
//  - submit_knowledge_card: Writes to shared state
//  - persist_data: Writes to shared state
//  - set_objective_status: Modifies global phase state
//  - next_phase: Modifies global phase state
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

// MARK: - Sub-Agent Tool Executor

/// Minimal tool executor for isolated sub-agents.
/// Only provides read-only access to artifacts and a completion tool.
actor SubAgentToolExecutor {
    // MARK: - Dependencies

    private let artifactRepository: ArtifactRepository

    // MARK: - Tool Definitions

    private lazy var tools: [ChatCompletionParameters.Tool] = buildTools()

    // MARK: - Initialization

    init(artifactRepository: ArtifactRepository) {
        self.artifactRepository = artifactRepository
    }

    // MARK: - Public API

    /// Get tool schemas for LLM
    func getToolSchemas() -> [ChatCompletionParameters.Tool] {
        return tools
    }

    /// Execute a tool call
    /// - Returns: JSON string result
    func execute(toolName: String, arguments: String) async -> String {
        let argsJSON: JSON
        if let data = arguments.data(using: .utf8) {
            argsJSON = (try? JSON(data: data)) ?? JSON()
        } else {
            argsJSON = JSON()
        }

        do {
            switch toolName {
            case "get_artifact":
                return try await executeGetArtifact(args: argsJSON)

            case "get_artifact_summary":
                return try await executeGetArtifactSummary(args: argsJSON)

            case "return_result":
                // This is handled by AgentRunner, just return success
                return "{\"status\": \"result_captured\"}"

            default:
                return errorResult("Tool not available for sub-agents: \(toolName)")
            }
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    // MARK: - Tool Implementations

    private func executeGetArtifact(args: JSON) async throws -> String {
        guard let artifactId = args["artifact_id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactId.isEmpty else {
            throw SubAgentToolError.invalidParameters("artifact_id is required")
        }

        // Safe: Actor-isolated read from shared repository
        guard let artifact = await artifactRepository.getArtifactRecord(id: artifactId) else {
            throw SubAgentToolError.notFound("Artifact not found: \(artifactId)")
        }

        var result = JSON()
        result["status"].string = "completed"
        result["artifact"] = artifact
        return result.rawString() ?? "{}"
    }

    private func executeGetArtifactSummary(args: JSON) async throws -> String {
        guard let artifactId = args["artifact_id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactId.isEmpty else {
            throw SubAgentToolError.invalidParameters("artifact_id is required")
        }

        // Safe: Actor-isolated read from shared repository
        guard let artifact = await artifactRepository.getArtifactRecord(id: artifactId) else {
            throw SubAgentToolError.notFound("Artifact not found: \(artifactId)")
        }

        var result = JSON()
        result["status"].string = "completed"
        result["artifact_id"].string = artifactId
        result["filename"].string = artifact["filename"].string
        result["summary"].string = artifact["summary"].string ?? "No summary available"
        result["content_type"].string = artifact["content_type"].string
        return result.rawString() ?? "{}"
    }

    private func errorResult(_ message: String) -> String {
        var result = JSON()
        result["status"].string = "error"
        result["error"].string = message
        return result.rawString() ?? "{\"status\": \"error\"}"
    }

    // MARK: - Tool Schema Building

    private func buildTools() -> [ChatCompletionParameters.Tool] {
        [
            buildGetArtifactTool(),
            buildGetArtifactSummaryTool(),
            buildReturnResultTool()
        ]
    }

    private func buildGetArtifactTool() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Retrieve complete artifact record including full extracted text content.
                Use this when you need the actual document content for detailed analysis.
                Returns the full artifact with extracted_text field containing the document content.
                """,
            properties: [
                "artifact_id": JSONSchema(
                    type: .string,
                    description: "Unique identifier of the artifact to retrieve"
                )
            ],
            required: ["artifact_id"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "get_artifact",
                strict: false,
                description: "Retrieve complete artifact with full extracted text content",
                parameters: schema
            )
        )
    }

    private func buildGetArtifactSummaryTool() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Retrieve just the summary of an artifact (not the full text).
                Use this for quick reference or to decide if full content is needed.
                Faster and lighter than get_artifact.
                """,
            properties: [
                "artifact_id": JSONSchema(
                    type: .string,
                    description: "Unique identifier of the artifact"
                )
            ],
            required: ["artifact_id"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "get_artifact_summary",
                strict: false,
                description: "Retrieve artifact summary only (not full content)",
                parameters: schema
            )
        )
    }

    private func buildReturnResultTool() -> ChatCompletionParameters.Tool {
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
                - sources: Array of artifact IDs used
                - highlights: Key achievements or competencies
                - skills: Relevant skills demonstrated
                - metrics: Quantitative achievements if available
                """,
            properties: [
                "result": JSONSchema(
                    type: .object,
                    description: "The completed result object to return"
                )
            ],
            required: ["result"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "return_result",
                strict: false,
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
