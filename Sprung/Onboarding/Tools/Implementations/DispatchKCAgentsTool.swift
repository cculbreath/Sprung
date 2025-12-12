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

                The 'proposals' parameter is optional - if omitted, the tool will use proposals stored
                from the most recent propose_card_assignments call.
                """,
            properties: [
                "proposals": JSONSchema(
                    type: .array,
                    description: """
                        Array of card proposals to generate. Optional - if not provided, will use
                        proposals stored from the most recent propose_card_assignments call.
                        """,
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
            required: [],
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
        // Try to get proposals from input first, then fall back to stored proposals
        var proposalsJSON = params["proposals"].arrayValue

        if proposalsJSON.isEmpty {
            // Fall back to stored proposals from propose_card_assignments
            let storedProposals = await coordinator.state.getCardProposals()
            proposalsJSON = storedProposals.arrayValue

            if !proposalsJSON.isEmpty {
                Logger.info("🔄 DispatchKCAgentsTool: Using \(proposalsJSON.count) stored proposal(s) from previous propose_card_assignments", category: .ai)
            }
        }

        guard !proposalsJSON.isEmpty else {
            var error = JSON()
            error["status"].string = "error"
            error["message"].string = "No proposals provided in input and no stored proposals found. Call propose_card_assignments first."
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

        // Signal toolChoice chaining - LLM MUST call submit_knowledge_card next
        // This mandates the first card persistence; instructions emphasize iterating through all
        if result.successCount > 0 {
            response["next_required_tool"].string = OnboardingToolName.submitKnowledgeCard.rawValue
            response["cards_pending_persistence"].int = result.successCount
        }

        return .immediate(response)
    }

    private func buildInstructions(result: KCDispatchResult) -> String {
        if result.failureCount == 0 {
            return """
                All \(result.successCount) cards generated successfully.

                ⚠️ REQUIRED ACTION: You MUST now persist each card.

                For EACH card in the 'cards' array (all \(result.successCount) of them):
                1. Call `submit_knowledge_card` with the card data
                2. Wait for confirmation
                3. Repeat for the next card

                DO NOT skip any cards. DO NOT call next_phase until ALL cards are persisted.

                After all \(result.successCount) cards are persisted, call `next_phase` to proceed.
                """
        } else {
            return """
                \(result.successCount) cards succeeded, \(result.failureCount) failed.

                ⚠️ REQUIRED ACTION: You MUST persist all successful cards.

                For EACH successful card in the 'cards' array:
                1. Call `submit_knowledge_card` with the card data
                2. Wait for confirmation
                3. Repeat for the next card

                For failed cards (see 'failures' array):
                - You may retry with dispatch_kc_agents using just the failed proposals
                - Or skip if non-critical and inform the user

                DO NOT call next_phase until you've handled all cards.
                """
        }
    }
}
