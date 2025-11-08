import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetApplicantProfileTool: InterviewTool {
    private static let schema = JSONSchema(
        type: .object,
        description: """
            Present the applicant profile intake UI card to collect contact information.

            When this tool returns "waiting for user input", respond with: "Once you complete the form to the left we can continue."

            The user can upload a document, paste a URL, import from macOS Contacts, or enter data manually.
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
    var description: String { "Present profile intake UI. Response indicates waiting for user - reply: 'Once you complete the form to the left we can continue.'" }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Emit UI request to show the form
        await coordinator.eventBus.publish(.applicantProfileIntakeRequested(continuationId: UUID()))

        // Return completed - the tool's job is to present UI, which it has done
        // User's submitted data will arrive as a new user message
        var response = JSON()
        response["message"].string = "UI presented. Awaiting user input."
        response["status"].string = "completed"

        return .immediate(response)
    }
}
