import Foundation
import SwiftyJSON
import SwiftOpenAI

struct ValidateApplicantProfileTool: InterviewTool {
    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "validate_applicant_profile" }
    var description: String { "Present applicant profile validation UI and return user decision." }
    var parameters: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Present applicant profile for validation",
            properties: [
                "data": JSONSchema(type: .object, description: "The applicant profile data to validate")
            ],
            required: ["data"],
            additionalProperties: false
        )
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        let data = params["data"]
        guard data != .null else {
            throw ToolError.invalidParameters("data is required")
        }

        let prompt = OnboardingValidationPrompt(
            dataType: "applicant_profile",
            payload: data,
            message: "Review your contact details."
        )

        // Emit UI request to show the validation prompt
        await coordinator.eventBus.publish(.validationPromptRequested(prompt: prompt, continuationId: UUID()))

        // Return immediately - we'll handle the validation response as a new user message
        var response = JSON()
        response["status"].string = "awaiting_user_input"
        response["message"].string = "Applicant profile validation prompt has been presented to the user"

        return .immediate(response)
    }
}
