import Foundation
import SwiftyJSON
import SwiftOpenAI
struct GetValidatedApplicantProfileTool: InterviewTool {
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.validatedApplicantProfileData.rawValue }
    var description: String { "Retrieve validated and persisted ApplicantProfile. Returns {found: true/false, data: {name, email, phone, ...}, message}." }
    var parameters: JSONSchema {
        JSONSchema(
            type: .object,
            description: """
                Retrieve the validated and persisted ApplicantProfile data from coordinator state.
                Use this to access the user's confirmed contact information after it has been validated and stored. The profile contains name, email, phone, location, URLs, and social profiles.
                RETURNS:
                - If persisted: { "found": true, "data": { "name": "...", "email": "...", "phone": "...", "location": "...", "url": "...", "profiles": [...] }, "message": "Retrieved validated..." }
                - If not persisted: { "found": false, "message": "No validated applicant profile found..." }
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
        let profileExists = await coordinator.state.artifacts.applicantProfile != nil
        if profileExists {
            // Regenerate JSON from SwiftData to ensure image is included
            let freshJSON = await MainActor.run {
                let swiftDataProfile = coordinator.currentApplicantProfile()
                let draft = ApplicantProfileDraft(profile: swiftDataProfile)
                return draft.toSafeJSON()
            }
            // Strip base64 image data for LLM context (keep metadata but omit binary data)
            var llmSafeJSON = freshJSON
            if let imageData = llmSafeJSON["image"].string, !imageData.isEmpty {
                llmSafeJSON["image"].string = "[Image uploaded - binary data omitted]"
            }
            var additionalData = JSON()
            additionalData["found"].bool = true
            additionalData["data"] = llmSafeJSON
            return ToolResultHelpers.statusResponse(
                status: "completed",
                message: "Retrieved validated applicant profile data",
                additionalData: additionalData
            )
        } else {
            var additionalData = JSON()
            additionalData["found"].bool = false
            return ToolResultHelpers.statusResponse(
                status: "completed",
                message: "No validated applicant profile found. Profile has not been persisted yet.",
                additionalData: additionalData
            )
        }
    }
}
