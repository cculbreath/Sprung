import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Tool for updating the dossier WIP notes (scratchpad).
/// The LLM can use this to track dossier information collected during the interview.
/// Notes are included in WorkingMemory so the LLM can reference them on subsequent turns.
struct UpdateDossierNotesTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Update the dossier WIP notes (scratchpad) to track information collected during the interview.",
            properties: [
                "notes": JSONSchema(
                    type: .string,
                    description: "The complete notes content. This REPLACES any existing notes. Use newlines to organize information."
                ),
                "append": JSONSchema(
                    type: .boolean,
                    description: "If true, appends to existing notes instead of replacing. Default: false"
                )
            ],
            required: ["notes"]
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.updateDossierNotes.rawValue }

    var description: String {
        "Update dossier WIP notes (scratchpad) to track candidate information during the interview. Notes appear in WorkingMemory."
    }

    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let notes = try ToolResultHelpers.requireString(params["notes"].string, named: "notes")

        let shouldAppend = params["append"].boolValue

        if shouldAppend {
            let existingNotes = await coordinator.state.getDossierNotes()
            let combined = existingNotes.isEmpty ? notes : existingNotes + "\n" + notes
            await coordinator.state.setDossierNotes(combined)
        } else {
            await coordinator.state.setDossierNotes(notes)
        }

        var response = JSON()
        response["status"].string = "updated"
        response["notes_length"].int = notes.count
        response["mode"].string = shouldAppend ? "append" : "replace"

        return .immediate(response)
    }
}
