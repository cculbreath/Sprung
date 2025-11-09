import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetValidatedApplicantProfileTool: InterviewTool {
    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "validated_applicant_profile_data" }
    var description: String { "Retrieve validated and persisted ApplicantProfile. Returns {status, data: {name, email, phone, ...}} or not_found." }
    var parameters: JSONSchema {
        JSONSchema(
            type: .object,
            description: """
                Retrieve the validated and persisted ApplicantProfile data from coordinator state.

                Use this to access the user's confirmed contact information after it has been validated and stored. The profile contains name, email, phone, location, URLs, and social profiles.

                RETURNS:
                - If persisted: { "status": "success", "data": { "name": "...", "email": "...", "phone": "...", "location": "...", "url": "...", "profiles": [...] }, "message": "Retrieved validated..." }
                - If not persisted: { "status": "not_found", "message": "No validated applicant profile found..." }

                USAGE: Call when you need to reference the user's contact info after it has been persisted. Common scenarios:
                - Checking if profile photo exists (data.basics.image)
                - Verifying profile was persisted before moving to skeleton_timeline
                - Accessing user's name for personalized messages (only after profile is persisted)

                WORKFLOW: Only call this after applicant_profile objective is completed and persist_data has been called. Before that point, the profile doesn't exist in coordinator state.

                DO NOT: Call before profile is persisted - will return not_found. Don't use for validation - use validate_applicant_profile instead.
                """,
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
