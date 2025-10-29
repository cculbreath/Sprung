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
        let tokenId = UUID()
        await service.presentApplicantProfileIntake(continuationId: tokenId)

        let token = ContinuationToken(
            id: tokenId,
            toolName: name,
            resumeHandler: { input in
                if input["cancelled"].boolValue {
                    return .error(.userCancelled)
                }
                return .immediate(input)
            }
        )

        return .waiting(message: "Waiting for applicant profile intake", continuation: token)
    }
}
