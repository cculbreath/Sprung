import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetArtifactRecordTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Retrieve complete artifact record including extracted text content and full metadata.

                Use this to access the actual content of uploaded files/URLs. The artifact contains extracted text (from PDFs, DOCX, etc.) that you can parse for interview data.

                RETURNS:
                - If found: { "artifact": { "id", "filename", "extracted_text", "content_type", "uploaded_at", "target_phase_objectives", "file_url", ... } }
                - If not found: Returns error

                USAGE: Call after list_artifacts identifies relevant artifacts. Parse extracted_text to extract ApplicantProfile, timeline entries, or other structured data.

                WORKFLOW:
                1. list_artifacts to see what's available
                2. get_artifact with specific artifact_id
                3. Parse artifact.extracted_text for relevant information
                4. Extract structured data (profile, timeline, etc.)
                5. Call validate_* or create_timeline_card with extracted data

                Common patterns:
                - Resume upload → get_artifact → extract profile + timeline skeleton
                - LinkedIn URL → get_artifact → extract profile information
                - Transcript upload → get_artifact → extract education entries

                ERROR: Returns not_found status if artifact_id doesn't exist. Use list_artifacts first to verify ID.
                """,
            properties: [
                "artifact_id": JSONSchema(
                    type: .string,
                    description: "Unique identifier of the artifact to retrieve. Obtain from list_artifacts response."
                )
            ],
            required: ["artifact_id"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "get_artifact" }
    var description: String { "Retrieve full artifact with extracted text content. Returns {artifact: {extracted_text, ...}}. Use to process uploaded files." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let artifactId = params["artifact_id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactId.isEmpty else {
            throw ToolError.invalidParameters("artifact_id is required and must be non-empty.")
        }

        // Get artifact record from coordinator state
        if let artifact = await coordinator.getArtifactRecord(id: artifactId) {
            var response = JSON()
            response["status"].string = "completed"
            response["artifact"] = artifact
            return .immediate(response)
        } else {
            throw ToolError.executionFailed("No artifact found with ID: \(artifactId)")
        }
    }
}
