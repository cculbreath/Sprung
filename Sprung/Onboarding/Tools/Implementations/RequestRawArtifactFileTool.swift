import Foundation
import SwiftyJSON
import SwiftOpenAI

struct RequestRawArtifactFileTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Request access to the original raw file (PDF, DOCX, image, etc.) associated with an artifact.

                Most artifact processing uses extracted_text from get_artifact. Use this only when you need the original file (e.g., for profile photos, PDFs requiring special handling).

                RETURNS:
                - Success: { "status": "success", "artifact_id": "<id>", "file_url": "<url>", "filename": "...", "content_type": "...", "size_bytes": ... }
                - Not found: { "status": "not_found", "artifact_id": "<id>", "message": "No artifact found..." }
                - No file: { "status": "error", "message": "Artifact does not have an associated file URL." }
                - File deleted: { "status": "file_not_found", "file_url": "<url>", "message": "The file...no longer exists." }

                USAGE: Rarely needed in Phase 1. Most text extraction is handled automatically. Use only for:
                - Profile photos (basics.image) where you need the image file URL
                - Special cases requiring original file format

                WORKFLOW:
                1. list_artifacts or get_artifact to identify artifact
                2. request_raw_file to get original file URL
                3. Use file_url for image storage or special processing

                DO NOT: Use this for text extraction - get_artifact already provides extracted_text. This is for accessing the binary/original file only.
                """,
            properties: [
                "artifact_id": JSONSchema(
                    type: .string,
                    description: "Unique identifier of the artifact whose original file is needed. Obtain from list_artifacts or get_artifact."
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

    var name: String { "request_raw_file" }
    var description: String { "Get original file URL for artifact. Returns {status, file_url, filename}. Rarely needed - use get_artifact for text content." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let artifactId = params["artifact_id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactId.isEmpty else {
            throw ToolError.invalidParameters("artifact_id is required and must be non-empty.")
        }

        // Get the artifact record to find the file URL
        guard let artifact = await coordinator.getArtifactRecord(id: artifactId) else {
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
