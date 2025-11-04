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
        // Check if there's an active upload request
        await MainActor.run {
            !service.pendingUploadRequests.isEmpty
        }
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        let reason = params["reason"].string

        // Get the current upload requests
        let uploadRequests = await MainActor.run { service.pendingUploadRequests }

        guard let firstRequest = uploadRequests.first else {
            var response = JSON()
            response["status"].string = "error"
            response["message"].string = "No active upload request to cancel."
            return .immediate(response)
        }

        // Cancel upload via coordinator (which emits event)
        await service.coordinator.cancelUploadRequest(id: firstRequest.id)

        // Build response
        var response = JSON()
        response["status"].string = "cancelled"
        response["upload_id"].string = firstRequest.id.uuidString
        if let reason {
            response["reason"].string = reason
        }

        // Include the cancel message if it was provided in the upload metadata
        if let cancelMessage = firstRequest.metadata.cancelMessage {
            response["cancel_message"].string = cancelMessage
        }

        return .immediate(response)
    }
}
