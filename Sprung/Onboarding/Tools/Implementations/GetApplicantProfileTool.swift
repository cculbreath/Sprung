import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetApplicantProfileTool: InterviewTool {
    private static let schema = JSONSchema(
        type: .object,
        description: """
            Present the applicant profile intake UI card in the tool pane to collect contact information.

            The user can provide contact info via multiple methods:
            - Upload a resume/document (PDF, DOCX) for automatic extraction
            - Paste a LinkedIn URL or personal website URL
            - Import from macOS Contacts app
            - Enter data manually in the form

            RETURNS: Waiting state while UI card is active: { "status": "waiting_for_user_input", "message": "Waiting for user to complete profile intake" }

            When user completes the intake, continuation resumes with: { "status": "<completed|cancelled>", "mode": "<upload|url|manual|contacts>", "message": "Profile intake completed." }

            USAGE: Call once at the start of Phase 1 after sending welcome message. The card remains active until user submits. Guide user to complete the card in the tool pane rather than requesting details via chat.

            WORKFLOW: After intake completes, an ArtifactRecord is created if user uploaded/pasted content. You must parse the artifact to extract ApplicantProfile basics, then call validate_applicant_profile for user confirmation.

            DO NOT: Re-request contact details via chat while the card is active. The tool pane UI is the primary collection surface.
            """,
        properties: [:],
        required: [],
        additionalProperties: false
    )

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "get_applicant_profile" }
    var description: String { "Present profile intake UI card (upload/URL/manual/contacts). Returns waiting state. Guide user to complete card in tool pane." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let continuationId = UUID()

        // Create continuation for user input
        let continuation = ContinuationToken(
            id: continuationId,
            toolName: name,
            uiRequest: .applicantProfileIntake
        ) { userInput in
            // When user completes the profile intake, return the status
            var response = JSON()
            response["status"] = userInput["status"]
            response["mode"] = userInput["mode"]

            if userInput["cancelled"].bool == true {
                response["message"].string = "Profile intake cancelled by user."
            } else {
                response["message"].string = "Profile intake completed."
            }

            return .immediate(response)
        }

        // Return waiting state - tool response will be sent when continuation is resumed
        return .waiting(
            message: "Waiting for user to complete profile intake",
            continuation: continuation
        )
    }
}
