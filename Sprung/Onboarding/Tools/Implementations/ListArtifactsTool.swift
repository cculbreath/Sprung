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

    private let service: OnboardingInterviewService

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    var name: String { "list_artifacts" }
    var description: String { "Returns summaries of all stored artifacts." }
    var parameters: JSONSchema { Self.schema }

    func isAvailable() async -> Bool {
        await MainActor.run { self.service.hasArtifacts() }
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        let summaries = await MainActor.run {
            service.artifactSummaries()
        }

        var response = JSON()
        response["count"].int = summaries.count
        response["artifacts"] = JSON(summaries)
        return .immediate(response)
    }
}
