import Foundation
import SwiftyJSON
import SwiftOpenAI

struct ListArtifactsTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "List stored onboarding artifacts with key metadata.",
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "list_artifacts" }
    var description: String { "Returns summaries of all stored artifacts." }
    var parameters: JSONSchema { Self.schema }

    func isAvailable() async -> Bool {
        let summaries = await coordinator.listArtifactSummaries()
        return !summaries.isEmpty
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        let summaries = await coordinator.listArtifactSummaries()

        var response = JSON()
        response["count"].int = summaries.count
        response["artifacts"] = JSON(summaries)
        return .immediate(response)
    }
}
