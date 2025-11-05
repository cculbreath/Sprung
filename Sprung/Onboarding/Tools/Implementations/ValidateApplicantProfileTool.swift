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
        let continuationId = UUID()

        let token = ContinuationToken(
            id: continuationId,
            toolName: name,
            initialPayload: JSON([
                "status": "waiting",
                "tool": name,
                "message": "Waiting for applicant profile validation"
            ]),
            uiRequest: .validationPrompt(prompt),
            resumeHandler: { input in
                if input["cancelled"].boolValue {
                    return .error(.userCancelled)
                }

                var response = JSON()
                response["status"].string = input["status"].stringValue
                if input["updatedData"].exists() {
                    response["updatedData"] = input["updatedData"]
                }
                if input["changes"].exists() {
                    response["changes"] = input["changes"]
                }
                if let notes = input["notes"].string {
                    response["notes"].string = notes
                }
                return .immediate(response)
            }
        )

        return .waiting(message: "Waiting for applicant profile validation", continuation: token)
    }
}
