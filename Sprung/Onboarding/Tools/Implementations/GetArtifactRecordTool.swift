import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetArtifactRecordTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Retrieve the full JSON record for a stored onboarding artifact.",
            properties: [
                "artifact_id": JSONSchema(
                    type: .string,
                    description: "Identifier of the artifact record to fetch."
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
    var description: String { "Returns the metadata and extracted content for an artifact." }
    var parameters: JSONSchema { Self.schema }

    func isAvailable() async -> Bool {
        await MainActor.run { self.service.hasArtifacts() }
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let artifactId = params["artifact_id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactId.isEmpty else {
            throw ToolError.invalidParameters("artifact_id must be a non-empty string.")
        }

        let record = await MainActor.run {
            service.artifactRecordDetail(id: artifactId)
        }

        guard let record else {
            throw ToolError.executionFailed("Artifact not found for id=\(artifactId).")
        }

        return .immediate(record)
    }
}
