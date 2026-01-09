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
            RETURNS: { "message": "UI presented. Awaiting user input.", "status": "completed" }
            The tool completes immediately after presenting UI. When user completes the intake, you receive a new user message with the completion status and mode.
            USAGE: Call once at the start of Phase 1 after sending welcome message. The card remains active until user submits. Guide user to complete the card in the tool pane rather than requesting details via chat.
            WORKFLOW: After intake completes, an ArtifactRecord is created if user uploaded/pasted content. You must parse the artifact to extract ApplicantProfile basics, then call validate_applicant_profile for user confirmation.
            DO NOT: Re-request contact details via chat while the card is active. The tool pane UI is the primary collection surface.
            """,
        properties: [:],
        required: [],
        additionalProperties: false
    )
    private weak var coordinator: OnboardingInterviewCoordinator?
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.getApplicantProfile.rawValue }
    var description: String { "Present profile intake UI card (upload/URL/manual/contacts). Returns immediately - intake completion arrives as user message." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
        // Emit UI request to show the profile intake card
        await coordinator.eventBus.publish(.toolpane(.applicantProfileIntakeRequested))
        // Block until user completes the action or interrupts
        let result = await coordinator.uiToolContinuationManager.awaitUserAction(toolName: name)
        return .immediate(result.toJSON())
    }
}
