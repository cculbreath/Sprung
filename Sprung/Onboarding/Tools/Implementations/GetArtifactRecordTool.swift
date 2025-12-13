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
    var description: String { "Retrieve full artifact with extracted text content. Returns {artifact: {extracted_text, ...}}. Use to process uploaded files." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let artifactId = params["artifact_id"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artifactId.isEmpty else {
            throw ToolError.invalidParameters("artifact_id is required and must be non-empty.")
        }
        // Get artifact record from coordinator state
        if let artifact = await coordinator.getArtifactRecord(id: artifactId) {
            var response = JSON()
            response["status"].string = "completed"
            response["artifact"] = artifact
            return .immediate(response)
        } else {
            throw ToolError.executionFailed("No artifact found with ID: \(artifactId)")
        }
    }
}
