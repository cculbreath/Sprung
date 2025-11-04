import Foundation
import SwiftyJSON
import SwiftOpenAI

struct RequestRawArtifactFileTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Request access to the raw file for a stored artifact.",
            properties: [
                "artifact_id": JSONSchema(
                    type: .string,
                    description: "The unique identifier of the artifact whose raw file is requested."
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
    var description: String { "Access the original file for a stored artifact." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let artifactId = params["artifact_id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactId.isEmpty else {
            throw ToolError.invalidParameters("artifact_id is required and must be non-empty.")
        }

        // Get the artifact to find the file URL (coordinator queries StateCoordinator)
        guard let artifact = await service.coordinator.getArtifact(id: artifactId) else {
            var response = JSON()
            response["status"].string = "not_found"
            response["artifact_id"].string = artifactId
            response["message"].string = "No artifact found with ID: \(artifactId)"
            return .immediate(response)
        }

        // Extract file URL from artifact metadata
        let fileURL = artifact["file_url"].string
            ?? artifact["storageUrl"].string
            ?? artifact["url"].string

        guard let fileURL, !fileURL.isEmpty else {
            var response = JSON()
            response["status"].string = "error"
            response["artifact_id"].string = artifactId
            response["message"].string = "Artifact does not have an associated file URL."
            return .immediate(response)
        }

        // Verify file exists if it's a local file URL
        if let url = URL(string: fileURL), url.isFileURL {
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            if !fileExists {
                var response = JSON()
                response["status"].string = "file_not_found"
                response["artifact_id"].string = artifactId
                response["file_url"].string = fileURL
                response["message"].string = "The file referenced by this artifact no longer exists."
                return .immediate(response)
            }
        }

        // Return the file information
        var response = JSON()
        response["status"].string = "success"
        response["artifact_id"].string = artifactId
        response["file_url"].string = fileURL
        response["filename"].string = artifact["filename"].string ?? "unknown"

        if let contentType = artifact["content_type"].string {
            response["content_type"].string = contentType
        }
        if let sizeBytes = artifact["size_bytes"].int {
            response["size_bytes"].int = sizeBytes
        }

        return .immediate(response)
    }
}
