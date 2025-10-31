import Foundation
import SwiftyJSON
import SwiftOpenAI

struct RequestRawArtifactFileTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Retrieve the original uploaded file for a stored artifact record.",
            properties: [
                "artifact_id": JSONSchema(
                    type: .string,
                    description: "Identifier of the artifact record to retrieve."
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

    var name: String { "request_raw_file" }
    var description: String { "Returns the original file associated with an artifact as base64 data." }
    var parameters: JSONSchema { Self.schema }

    func isAvailable() async -> Bool {
        await MainActor.run { self.service.hasArtifacts() }
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let artifactId = params["artifact_id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactId.isEmpty else {
            throw ToolError.invalidParameters("artifact_id must be a non-empty string.")
        }

        let payload = await MainActor.run {
            service.fetchRawArtifactFile(artifactId: artifactId)
        }

        guard let payload else {
            throw ToolError.executionFailed("Artifact not found or raw file unavailable for id=\(artifactId).")
        }

        var response = JSON()
        response["artifact_id"].string = payload.id
        if let sha = payload.sha256 {
            response["sha256"].string = sha
        }
        response["filename"].string = payload.filename
        response["content_type"].string = payload.mimeType
        response["size_bytes"].int = payload.data.count
        response["data_base64"].string = payload.data.base64EncodedString()

        return .immediate(response)
    }
}
