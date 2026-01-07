import Foundation
import SwiftyJSON
import SwiftOpenAI
/// Bootstrap tool used during conversation initialization.
/// The LLM calls this after receiving phase instructions to signal readiness,
/// triggering the system to send "I am ready to begin" and start the interview.
struct AgentReadyTool: InterviewTool {
    private static let schema: JSONSchema = PhaseSchemas.agentReadySchema()

    private let todoStore: InterviewTodoStore

    init(todoStore: InterviewTodoStore) {
        self.todoStore = todoStore
    }

    var name: String { OnboardingToolName.agentReady.rawValue }
    var description: String {
        "Signal ready to begin. Returns {status, next_required_tool, disable_after_use}."
    }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Populate todo list from PhaseOneScript (single source of truth)
        // Use setItemsFromScript to mark items as locked (LLM can't remove them)
        let phaseOneScript = PhaseOneScript()
        await todoStore.setItemsFromScript(phaseOneScript.initialTodoItems)

        var additionalData = JSON()
        additionalData["next_required_tool"].string = OnboardingToolName.getApplicantProfile.rawValue
        additionalData["disable_after_use"].bool = true
        additionalData["workflow_summary"].string = PromptLibrary.agentReadyWorkflow

        return ToolResultHelpers.statusResponse(
            status: "completed",
            additionalData: additionalData
        )
    }
}
