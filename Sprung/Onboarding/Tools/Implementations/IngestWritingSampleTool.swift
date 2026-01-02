//
//  IngestWritingSampleTool.swift
//  Sprung
//
//  Tool for LLM to ingest writing samples from text pasted in chat.
//  Creates an artifact record for the writing sample.
//
import CryptoKit
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

                ⚠️ NEVER use this tool for content from uploaded files - those are ALREADY artifacts!
                File uploads are automatically processed. Using this tool on uploaded file content
                will be detected as a duplicate and rejected.

                WORKFLOW:
                1. User pastes text in chat describing it as a writing sample
                2. Call this tool with the full text content and descriptive name
                3. The tool creates an artifact record (or returns duplicate_detected if content exists)

                RETURNS:
                - Success: { "status": "ingested", "artifact_id": "<uuid>", "name": "<name>", "character_count": <n> }
                - Duplicate: { "status": "duplicate_detected", "existing_artifact_id": "<uuid>", "message": "..." }

                NOTE: This is ONLY for text pasted in chat. Uploaded files are already artifacts.
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

        // Compute content hash for duplicate detection
        let contentHash = sha256Hex(content)

        // Check for duplicate content in existing artifacts
        let existingArtifacts = await coordinator.listArtifactSummaries()
        for artifact in existingArtifacts {
            // Check by hash if available
            if artifact["source_hash"].string == contentHash {
                let existingName = artifact["filename"].stringValue
                Logger.warning("📝 Duplicate writing sample detected (hash match): \(existingName)", category: .ai)
                return duplicateResponse(existingName: existingName, existingId: artifact["id"].stringValue)
            }
            // Check by content substring (handles case where original upload didn't have hash)
            // Need to fetch full artifact to get extracted_text
            if let artifactId = artifact["id"].string,
               let fullArtifact = await coordinator.getArtifactRecord(id: artifactId) {
                let existingContent = fullArtifact["extracted_text"].stringValue
                if !existingContent.isEmpty && contentMatchesExisting(content, existingContent) {
                    let existingName = fullArtifact["filename"].stringValue
                    Logger.warning("📝 Duplicate writing sample detected (content match): \(existingName)", category: .ai)
                    return duplicateResponse(existingName: existingName, existingId: artifactId)
                }
            }
        }

        // Create artifact record for the writing sample
        let artifactId = UUID()
        var artifactRecord = JSON()
        artifactRecord["id"].string = artifactId.uuidString
        artifactRecord["source_type"].string = "writing_sample"
        artifactRecord["filename"].string = "\(sampleName).txt"
        artifactRecord["extracted_text"].string = content
        artifactRecord["source_hash"].string = contentHash
        artifactRecord["interview_context"].bool = true  // Full content sent to LLM
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

    // MARK: - Duplicate Detection Helpers

    /// Compute SHA256 hash of content
    private func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Check if content matches existing artifact content (normalized comparison)
    private func contentMatchesExisting(_ newContent: String, _ existingContent: String) -> Bool {
        // Normalize whitespace for comparison
        let normalizedNew = newContent.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        let normalizedExisting = existingContent.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")

        // Check for exact match or substantial overlap (90% similar)
        if normalizedNew == normalizedExisting {
            return true
        }

        // Check if one contains the other (covers excerpts)
        let shorter = normalizedNew.count < normalizedExisting.count ? normalizedNew : normalizedExisting
        let longer = normalizedNew.count < normalizedExisting.count ? normalizedExisting : normalizedNew

        // If shorter is at least 80% of longer and is contained, it's a match
        if shorter.count > 500 && Double(shorter.count) / Double(longer.count) > 0.8 {
            return longer.contains(shorter)
        }

        return false
    }

    /// Build response for duplicate detection
    private func duplicateResponse(existingName: String, existingId: String) -> ToolResult {
        var response = JSON()
        response["status"].string = "duplicate_detected"
        response["existing_artifact_id"].string = existingId
        response["existing_artifact_name"].string = existingName
        response["message"].string = "This content already exists as artifact '\(existingName)'. Do NOT call ingest_writing_sample again with this content."
        response["next_action"].string = """
            STOP: This writing sample already exists as '\(existingName)'.
            Do NOT attempt to re-ingest it with a different name.
            The uploaded files have already been processed as artifacts.
            Move on to evaluate the existing writing samples for quality.
            """
        return .immediate(response)
    }
}
