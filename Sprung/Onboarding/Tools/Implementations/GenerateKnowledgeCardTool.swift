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

        let context = ExperienceContext(
            timelineEntry: params["experience"],
            artifacts: artifacts,
            transcript: transcript
        )

        do {
            let draft = try await agent.generateCard(for: context)
            var response = draft.toJSON()

            // Add validation nudge to guide LLM to validate the card
            response["next_action_hint"] = JSON("Call submit_for_validation(validation_type: \"knowledge_card\", data: <this draft>) to show the user and capture their feedback.")

            return .immediate(response)
        } catch let error as KnowledgeCardAgentError {
            return .error(.executionFailed(error.localizedDescription))
        } catch {
            return .error(.executionFailed("Knowledge card generation failed: \(error.localizedDescription)"))
        }
    }
}
