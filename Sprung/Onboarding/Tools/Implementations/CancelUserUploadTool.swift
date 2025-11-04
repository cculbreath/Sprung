import Foundation
import SwiftyJSON
import SwiftOpenAI

struct CancelUserUploadTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Dismiss the current upload request without providing files.",
            properties: [
                "reason": JSONSchema(
                    type: .string,
                    description: "Optional explanation for cancelling the upload."
                )
            ],
            required: [],
            additionalProperties: false
        )
    }()

    private let service: OnboardingInterviewService

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    var name: String { "cancel_user_upload" }
    var description: String { "Dismiss the active upload card and continue without collecting files." }
    var parameters: JSONSchema { Self.schema }

    func isAvailable() async -> Bool {
        // TODO: Check via event system
        return false
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        // TODO: Reimplement using event-driven architecture
        var response = JSON()
        response["status"] = "cancelled"
        return .immediate(response)
    }
}
