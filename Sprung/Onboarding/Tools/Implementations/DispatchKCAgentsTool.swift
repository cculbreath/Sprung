//
//  DispatchKCAgentsTool.swift
//  Sprung
//
//  Tool for dispatching parallel Knowledge Card (KC) generation agents.
//  The main coordinator calls this tool with card proposals, and KC agents
//  run in isolated threads to generate cards concurrently.
//

import Foundation
import SwiftyJSON

/// Tool that dispatches parallel KC agents to generate knowledge cards.
/// Each agent runs in an isolated conversation thread with its own tool executor.
/// Results are collected and returned to the main coordinator for persistence.
struct DispatchKCAgentsTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Dispatch parallel agents to generate knowledge cards. Each agent runs in an isolated
                thread with access to artifact content. Returns completed cards for validation.

                IMPORTANT: Call this after propose_card_assignments when user is ready to generate cards.
                """,
            properties: [
                "proposals": JSONSchema(
                    type: .array,
                    description: "Array of card proposals to generate",
                    items: JSONSchema(
                        type: .object,
                        properties: [
                            "card_id": JSONSchema(
                                type: .string,
                                description: "Unique ID for this card (UUID)"
                            ),
                            "card_type": JSONSchema(
                                type: .string,
                                description: "Type of card: 'job' or 'skill'"
                            ),
                            "title": JSONSchema(
                                type: .string,
                                description: "Title of the card (e.g., 'Senior Engineer at Company X')"
                            ),
                            "timeline_entry_id": JSONSchema(
                                type: .string,
                                description: "Optional: ID of the timeline entry this card relates to"
                            ),
                            "assigned_artifact_ids": JSONSchema(
                                type: .array,
                                description: "Array of artifact IDs assigned to this card",
                                items: JSONSchema(type: .string)
                            ),
                            "notes": JSONSchema(
                                type: .string,
                                description: "Optional notes for the KC agent about this card"
                            )
                        ],
                        required: ["card_id", "card_type", "title"]
                    )
                )
            ],
            required: ["proposals"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.dispatchKCAgents.rawValue }

    var description: String {
        "Dispatch parallel agents to generate knowledge cards from artifact content"
    }

    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let proposalsJSON = params["proposals"].arrayValue
        guard !proposalsJSON.isEmpty else {
            var error = JSON()
            error["status"].string = "error"
            error["message"].string = "No proposals provided"
            return .immediate(error)
        }

        Logger.info("🚀 DispatchKCAgentsTool: Dispatching \(proposalsJSON.count) KC agent(s)", category: .ai)

        // Convert JSON proposals to CardProposal structs
        let proposals = proposalsJSON.map { json -> CardProposal in
            CardProposal(
                cardId: json["card_id"].stringValue,
                cardType: json["card_type"].stringValue,
                title: json["title"].stringValue,
                timelineEntryId: json["timeline_entry_id"].string,
                assignedArtifactIds: json["assigned_artifact_ids"].arrayValue.map { $0.stringValue },
                notes: json["notes"].string
            )
        }

        // Get all artifact summaries for agent reference
        let allSummaries = await coordinator.listArtifactSummaries()

        // Get the KC agent service and dispatch
        let kcAgentService = await coordinator.getKCAgentService()
        let result = await kcAgentService.dispatchAgents(
            proposals: proposals,
            allSummaries: allSummaries
        )

        // Build response
        var response = JSON()
        response["status"].string = "completed"
        response["total_cards"].int = result.cards.count
        response["success_count"].int = result.successCount
        response["failure_count"].int = result.failureCount
        response["duration_seconds"].double = result.totalDuration

        // Include successful cards for coordinator to persist
        var successfulCards = JSON([])
        for card in result.successfulCards {
            successfulCards.arrayObject?.append(card.toJSON().dictionaryObject ?? [:])
        }
        response["cards"] = successfulCards

        // Include failures for coordinator awareness
        if !result.failedCards.isEmpty {
            var failures = JSON([])
            for card in result.failedCards {
                var failure = JSON()
                failure["card_id"].string = card.cardId
                failure["title"].string = card.title
                failure["error"].string = card.error
                failures.arrayObject?.append(failure.dictionaryObject ?? [:])
            }
            response["failures"] = failures
        }

        // Instructions for next steps
        response["instructions"].string = buildInstructions(result: result)

        return .immediate(response)
    }

    private func buildInstructions(result: KCDispatchResult) -> String {
        if result.failureCount == 0 {
            return """
                All \(result.successCount) cards generated successfully.

                NEXT STEPS:
                1. Review each card in the 'cards' array for quality and completeness
                2. For each valid card, call submit_knowledge_card to persist it
                3. After all cards are persisted, proceed to the next phase
                """
        } else {
            return """
                \(result.successCount) cards succeeded, \(result.failureCount) failed.

                NEXT STEPS:
                1. Review and persist the successful cards using submit_knowledge_card
                2. For failed cards, you may:
                   - Retry by calling dispatch_kc_agents with just the failed proposals
                   - Skip them if non-critical
                   - Ask the user for additional information
                3. Check the 'failures' array for error details
                """
        }
    }
}
