//
//  IngestWritingSampleTool.swift
//  Sprung
//
//  Tool for LLM to ingest writing samples from text pasted in chat.
//  Creates an artifact record for the writing sample.
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
                3. The tool creates an artifact record

                RETURNS: { "status": "ingested", "artifact_id": "<uuid>", "name": "<name>", "character_count": <n> }

                NOTE: This is for text pasted in chat. For file uploads, use get_user_upload with type "writing_sample".
                """,
            properties: [
                "name": MiscSchemas.writingSampleName,
                "content": MiscSchemas.writingSampleContent,
                "writing_type": MiscSchemas.writingSampleType,
                "context": MiscSchemas.writingSampleContext
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
        let sampleName = try ToolResultHelpers.requireString(params["name"].string, named: "name")
        let content = try ToolResultHelpers.requireString(params["content"].string, named: "content")
        let writingType = try ToolResultHelpers.requireString(params["writing_type"].string, named: "writing_type")

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
            Writing sample captured successfully. Evaluate quality:
            - Is it substantial (150+ words of prose)?
            - Does it show the candidate's authentic voice?

            If inadequate, ask for a longer or more personal sample.
            If user has no more samples but corpus is sparse, check prior artifacts for strong writing to excerpt.
            If the writing is genuinely strong or exceptional, acknowledge it—but no praise needed for mediocre writing.
            Mark one_writing_sample.ingest_sample as completed when you have at least one quality sample.
            """

        return .immediate(response)
    }
}
