import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetArtifactRecordTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Retrieve full metadata for a specific artifact by ID.",
            properties: [
                "artifact_id": JSONSchema(
                    type: .string,
                    description: "The unique identifier of the artifact to retrieve."
                )
            ],
            required: ["artifact_id"],
            additionalProperties: false
        )
    }()

    private let service: OnboardingInterviewService

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    var name: String { "get_artifact" }
    var description: String { "Retrieve complete metadata and content for a specific artifact by ID." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let artifactId = params["artifact_id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactId.isEmpty else {
            throw ToolError.invalidParameters("artifact_id is required and must be non-empty.")
        }

        // Get artifact from coordinator (which queries StateCoordinator)
        if let artifact = await service.coordinator.getArtifact(id: artifactId) {
            var response = JSON()
            response["status"].string = "found"
            response["artifact"] = artifact
            return .immediate(response)
        } else {
            var response = JSON()
            response["status"].string = "not_found"
            response["artifact_id"].string = artifactId
            response["message"].string = "No artifact found with ID: \(artifactId)"
            return .immediate(response)
        }
    }
}
