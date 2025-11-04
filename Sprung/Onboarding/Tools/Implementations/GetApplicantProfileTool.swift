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
        let continuationId = UUID()

        var waitingPayload = JSON()
        waitingPayload["status"].string = "waiting"
        waitingPayload["tool"].string = name
        waitingPayload["message"].string = "Waiting for applicant profile input"

        let token = ContinuationToken(
            id: continuationId,
            toolName: name,
            initialPayload: waitingPayload,
            uiRequest: .applicantProfileIntake,
            resumeHandler: { input in
                if input["cancelled"].boolValue {
                    return .error(.userCancelled)
                }

                // Return the profile data from user input
                var response = JSON()
                response["status"].string = "completed"
                response["profile"] = input["profile"]
                response["source"].string = input["source"].stringValue
                return .immediate(response)
            }
        )

        return .waiting(message: "Waiting for applicant profile input", continuation: token)
    }
}
