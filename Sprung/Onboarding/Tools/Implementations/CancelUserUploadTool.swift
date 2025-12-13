import Foundation
import SwiftyJSON
import SwiftOpenAI
struct CancelUserUploadTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Dismiss the currently active upload request card without requiring user to provide files.
                Use this when user indicates they don't have files to upload or want to skip the upload step. The upload card is removed and workflow continues.
                RETURNS: { "status": "cancelled", "upload_id": "<id>", "cancel_message": "<message-if-provided>" }
                USAGE: Call when user explicitly declines upload ("I don't have that", "skip this", "do it manually instead"). Allows workflow to proceed without files.
                WORKFLOW:
                1. get_user_upload presented upload card
                2. User indicates they want to skip ("I don't have a resume")
                3. Call cancel_user_upload to dismiss card
                4. Proceed with alternative data collection (chat interview, manual entry, etc.)
                ERROR: Will fail if no upload request is currently active. Only call when an upload card is on screen.
                DO NOT: Cancel uploads preemptively - wait for user signal. Some users need time to locate files.
                """,
            properties: [
                "reason": UserInteractionSchemas.cancelReason
            ],
            required: [],
            additionalProperties: false
        )
    }()
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.cancelUserUpload.rawValue }
    var description: String { "Dismiss active upload card. Returns {status: cancelled}. Use when user wants to skip upload and provide data via chat instead." }
    var parameters: JSONSchema { Self.schema }
    func isAvailable() async -> Bool {
        // Check if there's an active upload request
        await MainActor.run {
            !coordinator.pendingUploadRequests.isEmpty
        }
    }
    func execute(_ params: JSON) async throws -> ToolResult {
        let reason = params["reason"].string
        // Get the current upload requests
        let uploadRequests = await MainActor.run { coordinator.pendingUploadRequests }
        guard let firstRequest = uploadRequests.first else {
            var response = JSON()
            response["status"].string = "completed"
            response["error"].bool = true
            response["message"].string = "No active upload request to cancel."
            return .immediate(response)
        }
        // Cancel upload via coordinator (which emits event)
        await coordinator.cancelUploadRequest(id: firstRequest.id)
        // Build response
        var response = JSON()
        response["status"].string = "completed"
        response["cancelled"].bool = true
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
