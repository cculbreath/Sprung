import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Bootstrap tool used during conversation initialization.
/// The LLM calls this after receiving phase instructions to signal readiness,
/// triggering the system to send "I am ready to begin" and start the interview.
struct AgentReadyTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Signal that you have received and understood the phase instructions and are ready to begin the interview.

                This is a bootstrap tool used only during conversation initialization. After receiving developer instructions for a new phase, call this tool to acknowledge receipt and signal readiness. The system will then send the user-ready message to begin the conversation.

                RETURNS: { "status": "completed", "content": "ok" }

                USAGE: Call this immediately after receiving phase instructions, before attempting any other actions.
                """,
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }()

    private let eventBus: EventCoordinator

    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
    }

    var name: String { "agent_ready" }
    var description: String { "Signal that you are ready to begin after receiving phase instructions. Returns {status: completed, content: ok}." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Trigger "I am ready to begin" user message with tool_choice=auto
        var readyPayload = JSON()
        readyPayload["text"].string = "I am ready to begin"
        await eventBus.publish(.llmSendUserMessage(
            payload: readyPayload,
            isSystemGenerated: true
        ))

        Logger.info("🚀 Agent acknowledged readiness - sending 'I am ready to begin'", category: .ai)

        // Return simple acknowledgment
        var result = JSON()
        result["status"].string = "completed"
        result["content"].string = "ok"
        return .immediate(result)
    }
}
