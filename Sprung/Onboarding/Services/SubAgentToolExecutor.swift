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

    private let artifactRepository: any ArtifactStorageProtocol

    // MARK: - Tool Definitions

    private lazy var tools: [ChatCompletionParameters.Tool] = buildTools()

    // MARK: - Initialization

    init(artifactRepository: any ArtifactStorageProtocol) {
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

        // Sub-agents can easily blow past model context limits if we return multi-megabyte
        // extracted_text fields. Return a compact artifact view, truncating extracted_text.
        let maxExtractedChars = 180_000
        let extracted = artifact["extracted_text"].stringValue
        let extractedOriginalChars = extracted.count
        let extractedTruncated: String
        let didTruncate: Bool
        if extractedOriginalChars > maxExtractedChars {
            didTruncate = true
            extractedTruncated = String(extracted.prefix(maxExtractedChars)) + "\n\n[TRUNCATED: extracted_text exceeded \(maxExtractedChars) chars]"
        } else {
            didTruncate = false
            extractedTruncated = extracted
        }

        var compact = JSON()
        compact["id"].string = artifact["id"].string
        compact["filename"].string = artifact["filename"].string
        compact["content_type"].string = artifact["content_type"].string
        compact["size_bytes"].int = artifact["size_bytes"].int
        if let brief = artifact["brief_description"].string, !brief.isEmpty {
            compact["brief_description"].string = brief
        }
        if let summary = artifact["summary"].string, !summary.isEmpty {
            compact["summary"].string = summary
        }
        if !artifact["summary_metadata"].dictionaryValue.isEmpty {
            compact["summary_metadata"] = artifact["summary_metadata"]
        }
        // Keep selected metadata fields that help interpretation but avoid dumping huge blobs.
        if let title = artifact["metadata"]["title"].string, !title.isEmpty {
            compact["metadata"]["title"].string = title
        }
        if let purpose = artifact["metadata"]["purpose"].string, !purpose.isEmpty {
            compact["metadata"]["purpose"].string = purpose
        }
        compact["extracted_text"].string = extractedTruncated
        compact["extracted_text_original_chars"].int = extractedOriginalChars
        compact["extracted_text_truncated"].bool = didTruncate

        var result = JSON()
        result["status"].string = "completed"
        result["artifact"] = compact
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
        let chatSourceSchema = JSONSchema(
            type: .object,
            description: "A source excerpt from the user conversation used as evidence",
            properties: [
                "excerpt": JSONSchema(type: .string, description: "Direct quote from the user"),
                "context": JSONSchema(type: .string, description: "Why this excerpt matters / what it supports")
            ],
            required: ["excerpt", "context"],  // OpenAI strict mode requires all properties in required
            additionalProperties: false
        )

        // OpenAI strict mode requires ALL properties to be in required array
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
                    description: "Artifact IDs used as evidence (prefer non-empty); include assigned artifacts whenever possible.",
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
                - sources: Array of artifact IDs used
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
