import Foundation
import SwiftyJSON
import SwiftOpenAI

struct RequestRawArtifactFileTool: InterviewTool {
    private static let schema: JSONSchema = ArtifactSchemas.requestRawFile
    private weak var coordinator: OnboardingInterviewCoordinator?
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.requestRawFile.rawValue }
    var description: String { "Get original file URL for artifact. Returns {status, fileUrl, filename}. Rarely needed - use get_artifact for text content." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
        let artifactId = try ToolResultHelpers.requireString(
            params["artifactId"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
            named: "artifactId"
        )

        // Get the artifact record to find the file URL
        guard let artifact = await coordinator.getArtifactRecord(id: artifactId) else {
            var additionalData = JSON()
            additionalData["error"].bool = true
            additionalData["artifactId"].string = artifactId
            return ToolResultHelpers.statusResponse(
                status: "completed",
                message: "No artifact found with ID: \(artifactId)",
                additionalData: additionalData
            )
        }
        // Extract file URL from artifact metadata
        let fileURL = artifact["fileUrl"].string
            ?? artifact["storageUrl"].string
            ?? artifact["url"].string
        guard let fileURL, !fileURL.isEmpty else {
            var additionalData = JSON()
            additionalData["error"].bool = true
            additionalData["artifactId"].string = artifactId
            return ToolResultHelpers.statusResponse(
                status: "completed",
                message: "Artifact does not have an associated file URL.",
                additionalData: additionalData
            )
        }
        // Verify file exists if it's a local file URL
        if let url = URL(string: fileURL), url.isFileURL {
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            if !fileExists {
                var additionalData = JSON()
                additionalData["error"].bool = true
                additionalData["artifactId"].string = artifactId
                additionalData["fileUrl"].string = fileURL
                return ToolResultHelpers.statusResponse(
                    status: "completed",
                    message: "The file referenced by this artifact no longer exists.",
                    additionalData: additionalData
                )
            }
        }
        // Return the file information
        var response = JSON()
        response["status"].string = "completed"
        response["artifactId"].string = artifactId
        response["fileUrl"].string = fileURL
        response["filename"].string = artifact["filename"].string ?? "unknown"
        if let contentType = artifact["contentType"].string {
            response["contentType"].string = contentType
        }
        if let sizeBytes = artifact["sizeBytes"].int {
            response["sizeBytes"].int = sizeBytes
        }
        return .immediate(response)
    }
}
