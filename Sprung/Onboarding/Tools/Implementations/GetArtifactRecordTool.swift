import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Returns artifact with full extracted text (up to ~10,000 words).
struct GetArtifactRecordTool: InterviewTool {
    private static let schema: JSONSchema = ArtifactSchemas.getArtifact
    private unowned let coordinator: OnboardingInterviewCoordinator

    /// Maximum characters to return (~10,000 words)
    private let maxExtractedChars = 60_000

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.getArtifact.rawValue }
    var description: String { "Retrieve artifact with full extracted text content (up to ~10,000 words)." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        let artifactId = try ToolResultHelpers.requireString(
            params["artifact_id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
            named: "artifact_id"
        )

        // Get artifact record from coordinator state
        guard let artifact = await coordinator.artifactQueries.getArtifactRecord(id: artifactId) else {
            return ToolResultHelpers.executionFailed("No artifact found with ID: \(artifactId)")
        }

        // IMPORTANT: Do NOT include artifact["metadata"] - it can be 70KB+ for git repos
        var response = JSON()
        response["status"].string = "completed"
        response["artifact_id"].string = artifactId
        response["filename"].string = artifact["filename"].string
        response["content_type"].string = artifact["content_type"].string
        response["source_type"].string = artifact["source_type"].string

        // Return full extracted text up to limit
        let extractedText = artifact["extracted_text"].stringValue
        let originalLength = extractedText.count
        if !extractedText.isEmpty {
            if originalLength > maxExtractedChars {
                response["extracted_text"].string = String(extractedText.prefix(maxExtractedChars))
                response["truncated"].bool = true
                response["original_length"].int = originalLength
            } else {
                response["extracted_text"].string = extractedText
                response["truncated"].bool = false
            }
        } else {
            response["extracted_text"].string = ""
        }

        // Include summary metadata if available
        if let briefDesc = artifact["summary_metadata"]["brief_description"].string {
            response["brief_description"].string = briefDesc
        }
        if let docType = artifact["summary_metadata"]["document_type"].string {
            response["document_type"].string = docType
        }

        // For git repos, extract repository description from analysis
        let sourceType = artifact["source_type"].stringValue
        if sourceType == "git_repository" {
            if let repoDesc = artifact["metadata"]["analysis"]["repository_summary"]["description"].string {
                response["repository_description"].string = String(repoDesc.prefix(500))
            }
        }

        return .immediate(response)
    }
}
