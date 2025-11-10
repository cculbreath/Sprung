import Foundation
import SwiftyJSON
import SwiftOpenAI

struct ValidateApplicantProfileTool: InterviewTool {
    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "validate_applicant_profile" }
    var description: String { "Present applicant profile validation UI card. Returns immediately - validation response arrives as user message." }
    var parameters: JSONSchema {
        JSONSchema(
            type: .object,
            description: """
                Present applicant profile validation card in the tool pane for user review and confirmation.

                Displays the extracted/collected profile data in an editable UI where user can verify accuracy and make corrections before persisting.

                RETURNS: { "message": "UI presented. Awaiting user input.", "status": "completed" }

                The tool completes immediately after presenting UI. User validation response arrives as a new user message with status: "confirmed" or "rejected".

                USAGE: Call after extracting contact info from uploaded documents or manual entry. Always validate before calling persist_data. This is the confirmation surface that prevents storing incorrect data.

                WORKFLOW:
                1. Extract ApplicantProfile data from artifact or user input
                2. Call validate_applicant_profile with extracted data
                3. Tool returns immediately - validation card is now active
                4. User reviews, corrects if needed, and confirms/rejects
                5. You receive validation response message
                6. If confirmed, call persist_data(dataType: "applicant_profile", data: <validated-data>)

                DO NOT: Skip validation or call persist_data before user confirmation. Validation prevents data quality issues.
                """,
            properties: [
                "data": JSONSchema(
                    type: .object,
                    description: "The applicant profile data to validate (name, email, phone, location, URLs, social profiles). Should match ApplicantProfile schema."
                )
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
        await coordinator.eventBus.publish(.validationPromptRequested(prompt: prompt))

        // Return completed - the tool's job is to present UI, which it has done
        // User's validation response will arrive as a new user message
        var response = JSON()
        response["message"].string = "UI presented. Awaiting user input."
        response["status"].string = "completed"

        return .immediate(response)
    }
}
