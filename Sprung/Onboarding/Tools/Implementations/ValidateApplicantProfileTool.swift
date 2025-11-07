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

        // Return completed - the tool's job is to present UI, which it has done
        // User's validation response will arrive as a new user message
        var response = JSON()
        response["message"].string = "UI presented. Awaiting user input."
        response["status"].string = "completed"

        return .immediate(response)
    }
}
