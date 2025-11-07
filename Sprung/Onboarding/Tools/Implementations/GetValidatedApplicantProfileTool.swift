import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetValidatedApplicantProfileTool: InterviewTool {
    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "validated_applicant_profile_data" }
    var description: String { "Retrieve the validated and persisted ApplicantProfile data from the coordinator." }
    var parameters: JSONSchema {
        JSONSchema(
            type: .object,
            description: "No parameters required - returns the persisted applicant profile if available",
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Retrieve persisted applicant profile using public accessor
        let profile = await coordinator.applicantProfileJSON

        var response = JSON()

        if let profile = profile {
            response["status"].string = "success"
            response["data"] = profile
            response["message"].string = "Retrieved validated applicant profile data"
        } else {
            response["status"].string = "not_found"
            response["message"].string = "No validated applicant profile found. Profile has not been persisted yet."
        }

        return .immediate(response)
    }
}
