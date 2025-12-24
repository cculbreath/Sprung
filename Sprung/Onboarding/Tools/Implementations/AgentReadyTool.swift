import Foundation
import SwiftyJSON
import SwiftOpenAI
/// Bootstrap tool used during conversation initialization.
/// The LLM calls this after receiving phase instructions to signal readiness,
/// triggering the system to send "I am ready to begin" and start the interview.
struct AgentReadyTool: InterviewTool {
    private static let schema: JSONSchema = PhaseSchemas.agentReadySchema()
    init() {}
    var name: String { OnboardingToolName.agentReady.rawValue }
    var description: String {
        "Signal ready to begin. Returns {status, next_required_tool, disable_after_use}."
    }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        var additionalData = JSON()
        additionalData["next_required_tool"].string = OnboardingToolName.getApplicantProfile.rawValue
        additionalData["disable_after_use"].bool = true
        additionalData["workflow_summary"].string = """
            After profile intake completes, you'll be guided to:
            1. Offer profile photo upload (optional - user can skip)
            2. Offer resume/LinkedIn upload for timeline building (optional - user can dictate instead)
            Be proactive: Always call the upload tool BEFORE describing it to the user.
            Never ask if they want to upload - just show the upload UI and explain their options.
            """
        return ToolResultHelpers.statusResponse(
            status: "completed",
            additionalData: additionalData
        )
    }
}
