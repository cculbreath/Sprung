import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Returns artifact SUMMARY (metadata + summary text) only.
/// Full content is available to KC agents via their own get_artifact tool.
/// The coordinator doesn't need full content - it just orchestrates.
struct GetArtifactRecordTool: InterviewTool {
    private static let schema: JSONSchema = ArtifactSchemas.getArtifact
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.getArtifact.rawValue }
    var description: String { "Retrieve artifact summary and metadata. Full content is processed by KC agents, not the coordinator." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        let artifactId = try ToolResultHelpers.requireString(
            params["artifact_id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
            named: "artifact_id"
        )

        // Get artifact record from coordinator state
        guard let artifact = await coordinator.getArtifactRecord(id: artifactId) else {
            return ToolResultHelpers.executionFailed("No artifact found with ID: \(artifactId)")
        }

        // Return summary only - coordinator doesn't need full content or metadata
        // KC agents have their own get_artifact tool for full content
        // IMPORTANT: Do NOT include artifact["metadata"] - it can be 70KB+ for git repos
        var response = JSON()
        response["status"].string = "completed"
        response["artifact_id"].string = artifactId
        response["filename"].string = artifact["filename"].string
        response["content_type"].string = artifact["content_type"].string
        response["source_type"].string = artifact["source_type"].string

        // Use extracted_text as summary (that's where summaries are stored)
        // Truncate to prevent large content from being sent to coordinator
        let extractedText = artifact["extracted_text"].stringValue
        if !extractedText.isEmpty {
            // Take first 500 chars as summary preview
            let summaryPreview = String(extractedText.prefix(500))
            response["summary"].string = summaryPreview + (extractedText.count > 500 ? "..." : "")
        } else {
            response["summary"].string = "No summary available"
        }

        // For documents, include brief description from summary_metadata (if present)
        // These are small fields specifically designed for summaries
        if let briefDesc = artifact["summary_metadata"]["brief_description"].string {
            response["brief_description"].string = briefDesc
        }
        if let docType = artifact["summary_metadata"]["document_type"].string {
            response["document_type"].string = docType
        }

        // For git repos, extract repository description from analysis (small field)
        let sourceType = artifact["source_type"].stringValue
        if sourceType == "git_repository" {
            if let repoDesc = artifact["metadata"]["analysis"]["repository_summary"]["description"].string {
                response["repository_description"].string = String(repoDesc.prefix(300))
            }
        }

        // Notify that full content is available to KC agents
        response["note"].string = "Full content available to KC agents during card generation"

        return .immediate(response)
    }
}
