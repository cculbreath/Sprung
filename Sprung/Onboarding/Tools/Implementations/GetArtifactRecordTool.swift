import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetArtifactRecordTool: InterviewTool {
    private static let schema: JSONSchema = ArtifactSchemas.getArtifact
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.getArtifact.rawValue }
    var description: String { "Retrieve artifact content. Use max_chars for bounded retrieval. Returns {artifact: {...}}." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let artifactId = params["artifact_id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactId.isEmpty else {
            throw ToolError.invalidParameters("artifact_id is required and must be non-empty.")
        }

        let maxChars = params["max_chars"].int

        // Get artifact record from coordinator state
        guard var artifact = await coordinator.getArtifactRecord(id: artifactId) else {
            throw ToolError.executionFailed("No artifact found with ID: \(artifactId)")
        }

        // Apply max_chars truncation if specified
        if let limit = maxChars, limit > 0 {
            if let text = artifact["extracted_text"].string, text.count > limit {
                artifact["extracted_text"].string = String(text.prefix(limit))
                artifact["truncated"].bool = true
                artifact["original_length"].int = text.count
            }
        }

        var response = JSON()
        response["status"].string = "completed"
        response["artifact"] = artifact
        return .immediate(response)
    }
}
