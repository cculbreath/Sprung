import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Returns artifact with full extracted text (up to ~10,000 words).
struct GetArtifactRecordTool: InterviewTool {
    private static let schema: JSONSchema = ArtifactSchemas.getArtifact
    private weak var coordinator: OnboardingInterviewCoordinator?

    /// Maximum characters to return (~10,000 words)
    private let maxExtractedChars = 60_000

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.getArtifact.rawValue }
    var description: String { "Retrieve artifact with full extracted text content (up to ~10,000 words)." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
        let artifactId = try ToolResultHelpers.requireString(
            params["artifactId"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
            named: "artifactId"
        )

        // Get artifact record from coordinator state
        guard let artifact = await coordinator.getArtifactRecord(id: artifactId) else {
            return ToolResultHelpers.executionFailed("No artifact found with ID: \(artifactId)")
        }

        // IMPORTANT: Do NOT include artifact["metadata"] - it can be 70KB+ for git repos
        var response = JSON()
        response["status"].string = "completed"
        response["artifactId"].string = artifactId
        response["filename"].string = artifact["filename"].string
        response["contentType"].string = artifact["contentType"].string
        response["sourceType"].string = artifact["sourceType"].string

        // Return full extracted text up to limit
        let extractedText = artifact["extractedText"].stringValue
        let originalLength = extractedText.count
        if !extractedText.isEmpty {
            if originalLength > maxExtractedChars {
                response["extractedText"].string = String(extractedText.prefix(maxExtractedChars))
                response["truncated"].bool = true
                response["originalLength"].int = originalLength
            } else {
                response["extractedText"].string = extractedText
                response["truncated"].bool = false
            }
        } else {
            response["extractedText"].string = ""
        }

        // Include summary metadata if available
        if let briefDesc = artifact["summaryMetadata"]["briefDescription"].string {
            response["briefDescription"].string = briefDesc
        }
        if let docType = artifact["summaryMetadata"]["documentType"].string {
            response["documentType"].string = docType
        }

        // For git repos, extract repository description from analysis
        let sourceType = artifact["sourceType"].stringValue
        if sourceType == "git_repository" {
            if let repoDesc = artifact["metadata"]["analysis"]["repositorySummary"]["description"].string {
                response["repositoryDescription"].string = String(repoDesc.prefix(500))
            }
        }

        // Mark as ephemeral - full content will be pruned after N turns (default 3)
        // LLM can always call get_artifact again if needed
        response["ephemeral"].bool = true

        return .immediate(response)
    }
}
