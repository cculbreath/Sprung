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

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "get_applicant_profile" }
    var description: String { "Collect applicant profile information using the built-in intake flow." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Emit UI request to show the form
        await coordinator.eventBus.publish(.applicantProfileIntakeRequested(continuationId: UUID()))

        // Return immediately - we'll handle the form submission as a new user message
        var response = JSON()
        response["status"].string = "awaiting_user_input"
        response["message"].string = "Applicant profile form has been presented to the user"

        return .immediate(response)
    }
}
