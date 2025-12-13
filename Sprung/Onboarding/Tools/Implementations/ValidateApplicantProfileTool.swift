import Foundation
import SwiftyJSON
import SwiftOpenAI
struct ValidateApplicantProfileTool: InterviewTool {
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.validateApplicantProfile.rawValue }
    var description: String { "Present validation UI for profile data extracted from DOCUMENTS or URLS ONLY. Do NOT use for contact card or manual form submissions - those are pre-validated." }
    var parameters: JSONSchema {
        JSONSchema(
            type: .object,
            description: """
                Present validation UI for profile data extracted from UPLOADED DOCUMENTS or PASTED URLS ONLY.
                CRITICAL: Do NOT use this tool when user submits via:
                - Contact card import (already validated by user through UI)
                - Manual form entry (already validated by user through UI)
                ONLY use when profile data was extracted from:
                - Uploaded PDF/DOCX resume
                - Pasted LinkedIn/website URL
                These automated extractions require user validation to confirm accuracy.
                RETURNS: { "message": "UI presented. Awaiting user input.", "status": "completed" }
                The tool completes immediately after presenting UI. User validation response arrives as a new user message.
                WORKFLOW FOR DOCUMENT/URL EXTRACTIONS:
                1. Extract ApplicantProfile data from uploaded document or URL
                2. Call validate_applicant_profile with extracted data
                3. Tool returns immediately - validation card is now active
                4. User reviews, corrects if needed, and confirms/rejects
                5. You receive validation response message
                6. If confirmed, data is persisted automatically
                DO NOT call this tool for contact card imports or manual form submissions.
                """,
            properties: [
                "data": ValidationSchemas.applicantProfileData
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
        // Codex paradigm: Return pending - don't send tool response until user acts.
        // The tool output will be sent when user confirms/rejects validation.
        return .pendingUserAction
    }
}
