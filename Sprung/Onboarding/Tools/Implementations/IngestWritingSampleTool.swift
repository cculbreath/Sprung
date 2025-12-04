//
//  IngestWritingSampleTool.swift
//  Sprung
//
//  Tool for LLM to ingest writing samples from text pasted in chat.
//  Creates an artifact record for the writing sample for later style analysis.
//
import Foundation
import SwiftyJSON

/// Tool that allows the LLM to create a writing sample artifact from text provided in chat.
/// Users can paste their writing samples directly, and this tool captures them as artifacts.
struct IngestWritingSampleTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Ingest a writing sample from text provided by the user in chat.
                Use this when the user pastes or types a writing sample (cover letter, email, essay, etc.)
                directly into the conversation instead of uploading a file.

                WORKFLOW:
                1. User pastes text in chat describing it as a writing sample
                2. Call this tool with the full text content and descriptive name
                3. The tool creates an artifact record for later style analysis

                RETURNS: { "status": "ingested", "artifact_id": "<uuid>", "name": "<name>", "character_count": <n> }

                NOTE: This is for text pasted in chat. For file uploads, use get_user_upload with type "writing_sample".
                """,
            properties: [
                "name": JSONSchema(
                    type: .string,
                    description: "Descriptive name for the writing sample (e.g., 'Cover letter for Google', 'Professional email to client', 'Graduate school essay')"
                ),
                "content": JSONSchema(
                    type: .string,
                    description: "The full text content of the writing sample. Include the complete text exactly as provided by the user."
                ),
                "writing_type": JSONSchema(
                    type: .string,
                    description: "Type of writing sample",
                    enum: ["cover_letter", "email", "essay", "proposal", "report", "blog_post", "documentation", "other"]
                ),
                "context": JSONSchema(
                    type: .string,
                    description: "Optional context about the writing sample (when written, purpose, audience)"
                )
            ],
            required: ["name", "content", "writing_type"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator
    private let eventBus: EventCoordinator

    init(coordinator: OnboardingInterviewCoordinator, eventBus: EventCoordinator) {
        self.coordinator = coordinator
        self.eventBus = eventBus
    }

    var name: String { OnboardingToolName.ingestWritingSample.rawValue }
    var description: String { "Create a writing sample artifact from text pasted in chat by the user." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let sampleName = params["name"].string, !sampleName.isEmpty else {
            return .error(.invalidParameters("name is required"))
        }

        guard let content = params["content"].string, !content.isEmpty else {
            return .error(.invalidParameters("content is required - include the full text of the writing sample"))
        }

        guard let writingType = params["writing_type"].string else {
            return .error(.invalidParameters("writing_type is required"))
        }

        let context = params["context"].string

        // Create artifact record for the writing sample
        let artifactId = UUID()
        var artifactRecord = JSON()
        artifactRecord["id"].string = artifactId.uuidString
        artifactRecord["source_type"].string = "writing_sample"
        artifactRecord["filename"].string = "\(sampleName).txt"
        artifactRecord["extracted_text"].string = content
        artifactRecord["ingested_at"].string = ISO8601DateFormatter().string(from: Date())

        // Build metadata
        var metadata = JSON()
        metadata["name"].string = sampleName
        metadata["writing_type"].string = writingType
        metadata["character_count"].int = content.count
        metadata["word_count"].int = content.split(separator: " ").count
        metadata["source"].string = "chat_paste"
        if let context {
            metadata["context"].string = context
        }
        artifactRecord["metadata"] = metadata

        // Emit artifact record produced event for StateCoordinator to process
        await eventBus.publish(.artifactRecordProduced(record: artifactRecord))

        Logger.info("📝 Writing sample ingested: \(sampleName) (\(content.count) chars)", category: .ai)

        // Build response
        var response = JSON()
        response["status"].string = "ingested"
        response["artifact_id"].string = artifactId.uuidString
        response["name"].string = sampleName
        response["writing_type"].string = writingType
        response["character_count"].int = content.count
        response["word_count"].int = content.split(separator: " ").count

        response["next_action"].string = """
            Writing sample captured successfully. You can now:
            1. Ask if the user has more writing samples to share
            2. If style analysis is consented, analyze the writing style
            3. Mark one_writing_sample.ingest_sample as completed when done collecting samples
            """

        return .immediate(response)
    }
}
