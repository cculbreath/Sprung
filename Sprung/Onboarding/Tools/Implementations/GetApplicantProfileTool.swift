import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetApplicantProfileTool: InterviewTool {
    private static let schema = JSONSchema(
        type: .object,
        description: "Initiate the applicant profile intake flow.",
        properties: [:],
        required: [],
        additionalProperties: false
    )

    private let service: OnboardingInterviewService

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    var name: String { "get_applicant_profile" }
    var description: String { "Collect applicant profile information using the built-in intake flow." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // TODO: Reimplement using event-driven architecture
        // await service.presentApplicantProfileIntake(continuationId: tokenId)
        var response = JSON()
        response["status"] = "pending"
        return .immediate(response)
    }
}
