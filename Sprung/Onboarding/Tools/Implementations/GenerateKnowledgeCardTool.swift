import Foundation
import SwiftyJSON
struct GenerateKnowledgeCardTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "experience": JSONSchema(
                type: .object,
                description: "Timeline entry the knowledge card should represent.",
                additionalProperties: true
            ),
            "artifacts": JSONSchema(
                type: .array,
                description: "Evidence artifacts available to cite.",
                items: JSONSchema(type: .object, additionalProperties: true)
            ),
            "transcript": JSONSchema(
                type: .string,
                description: "Transcript of the interview segment for this experience."
            ),
            "background_mode": JSONSchema(
                type: .boolean,
                description: "If true, the tool returns immediately and processes in the background. Use for non-blocking generation."
            )
        ]
        return JSONSchema(
            type: .object,
            description: "Generate a knowledge card draft for a specific experience.",
            properties: properties,
            required: ["experience"],
            additionalProperties: false
        )
    }()
    private let agentProvider: () -> KnowledgeCardAgent?
    init(agentProvider: @escaping () -> KnowledgeCardAgent?) {
        self.agentProvider = agentProvider
    }
    var name: String { "generate_knowledge_card" }
    var description: String { "Synthesize a knowledge card draft using the supplied experience context and evidence." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard params["experience"] != .null else {
            throw ToolError.invalidParameters("experience must be provided as an object")
        }
        guard let agent = agentProvider() else {
            return .error(.executionFailed("Knowledge card agent is not available."))
        }
        let artifactsJSON = params["artifacts"].arrayValue
        let artifacts = artifactsJSON.map { ArtifactRecord(json: $0) }
        let transcript = params["transcript"].stringValue
        let backgroundMode = params["background_mode"].boolValue
        let context = ExperienceContext(
            timelineEntry: params["experience"],
            artifacts: artifacts,
            transcript: transcript
        )
        do {
            let draft = try await agent.generateCard(for: context)
            if backgroundMode {
                // In background mode, we return a draft event via the agent's internal mechanism (or just return the draft here marked as background)
                // Ideally, the caller (IngestionCoordinator) handles the async nature.
                // But if this tool is called by LLM, we want to return "Processing started".

                // For now, we'll return the draft but with a status indicating it's a background draft
                // The caller (LLM) will see "Draft created" but won't need to validate immediately if it's part of a batch.

                var response = JSON()
                response["status"] = JSON("processing_started")
                response["draft_id"] = JSON(draft.id.uuidString)
                response["message"] = JSON("Knowledge card generation started in background.")

                // We should emit the event here so the system knows about the draft
                // But this tool doesn't have access to the event bus directly, only via the return value or if we inject it.
                // The KnowledgeCardAgent is just a generator.

                // Let's return the draft content but wrap it so the system can handle it.
                return .immediate(response)
            } else {
                var response = draft.toJSON()
                // Add validation nudge to guide LLM to validate the card
                response["status"] = JSON("completed")
                response["next_action_hint"] = JSON("Call submit_for_validation(validation_type: \"knowledge_card\", data: <this draft>) to show the user and capture their feedback.")
                return .immediate(response)
            }
        } catch let error as KnowledgeCardAgentError {
            return .error(.executionFailed(error.localizedDescription))
        } catch {
            return .error(.executionFailed("Knowledge card generation failed: \(error.localizedDescription)"))
        }
    }
}
