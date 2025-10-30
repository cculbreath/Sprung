import Foundation
import SwiftyJSON
import SwiftOpenAI

struct RequestRawArtifactFileTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Retrieve the original uploaded file for a stored artifact record.",
            properties: [
                "sha256": JSONSchema(
                    type: .string,
                    description: "SHA256 hash of the artifact record to retrieve."
                )
            ],
            required: ["sha256"],
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

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let sha = params["sha256"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sha.isEmpty else {
            throw ToolError.invalidParameters("sha256 must be a non-empty string.")
        }

        guard let payload = service.fetchRawArtifactFile(sha256: sha) else {
            throw ToolError.executionFailed("Artifact not found or raw file unavailable for sha256=\(sha).")
        }

        var response = JSON()
        response["sha256"].string = payload.sha
        response["filename"].string = payload.filename
        response["content_type"].string = payload.mimeType
        response["size_bytes"].int = payload.data.count
        response["data_base64"].string = payload.data.base64EncodedString()

        return .immediate(response)
    }
}
