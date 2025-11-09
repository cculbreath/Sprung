import Foundation
import SwiftyJSON
import SwiftOpenAI

struct ListArtifactsTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                List all stored artifacts with summary metadata (ID, filename, upload time, content type, target objectives).

                Artifacts are created when users upload files or paste URLs via get_user_upload or get_applicant_profile. Each artifact contains extracted text and metadata.

                RETURNS: { "count": <number>, "artifacts": [{ "id", "filename", "content_type", "uploaded_at", "target_phase_objectives" }] }

                USAGE: Call to see what artifacts exist before requesting full content via get_artifact. Useful for understanding what data you have to work with, especially after user uploads.

                WORKFLOW:
                1. User uploads file(s) via get_user_upload
                2. System creates ArtifactRecord(s) with extracted text
                3. Call list_artifacts to see summary of available artifacts
                4. Use get_artifact to retrieve full content for processing

                Common use cases:
                - Check if user uploaded resume before asking for timeline details
                - Identify which artifacts are tagged for specific objectives
                - Verify artifact existence before processing

                Returns empty list if no artifacts exist yet.
                """,
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "list_artifacts" }
    var description: String { "List all stored artifacts with metadata. Returns {count, artifacts: [{id, filename, ...}]}. Use to check what uploads exist." }
    var parameters: JSONSchema { Self.schema }

    func isAvailable() async -> Bool {
        let summaries = await coordinator.listArtifactSummaries()
        return !summaries.isEmpty
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        let summaries = await coordinator.listArtifactSummaries()

        var response = JSON()
        response["count"].int = summaries.count
        response["artifacts"] = JSON(summaries)
        return .immediate(response)
    }
}
