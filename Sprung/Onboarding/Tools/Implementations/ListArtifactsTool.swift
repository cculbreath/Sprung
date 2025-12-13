import Foundation
import SwiftyJSON
import SwiftOpenAI

struct ListArtifactsTool: InterviewTool {
    private static let schema: JSONSchema = ArtifactSchemas.listArtifacts
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.listArtifacts.rawValue }
    var description: String { "List all stored artifacts with metadata. Returns {count, artifacts: [{id, filename, ...}]}. Use to check what uploads exist." }
    var parameters: JSONSchema { Self.schema }
    func isAvailable() async -> Bool {
        let summaries = await coordinator.listArtifactSummaries()
        return !summaries.isEmpty
    }
    func execute(_ params: JSON) async throws -> ToolResult {
        let summaries = await coordinator.listArtifactSummaries()
        var response = JSON()
        response["status"].string = "completed"
        response["count"].int = summaries.count
        response["artifacts"] = JSON(summaries)
        return .immediate(response)
    }
}
