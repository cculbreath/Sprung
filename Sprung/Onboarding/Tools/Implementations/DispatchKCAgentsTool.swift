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
            description: "Generate knowledge cards via parallel agents. Uses stored proposals from propose_card_assignments. Optional 'proposals' parameter overrides.",
            properties: [
                "proposals": KnowledgeCardSchemas.proposalsArray
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
            // Fall back to stored proposals from card merge (triggered by "Done with Uploads" button)
            let storedProposals = await coordinator.state.getCardProposals()
            proposalsJSON = storedProposals.arrayValue

            if !proposalsJSON.isEmpty {
                Logger.info("🔄 DispatchKCAgentsTool: Using \(proposalsJSON.count) stored proposal(s) from card merge", category: .ai)
            }
        }

        guard !proposalsJSON.isEmpty else {
            var error = JSON()
            error["status"].string = "error"
            error["message"].string = "No proposals provided. User must click 'Done with Uploads' button to trigger card merge first."
            return .immediate(error)
        }

        Logger.info("🚀 DispatchKCAgentsTool: Dispatching \(proposalsJSON.count) KC agent(s)", category: .ai)

        // Convert JSON proposals to CardProposal structs
        let proposals = proposalsJSON.map { json -> CardProposal in
            // Parse chat excerpts if provided
            let chatExcerpts = json["chat_excerpts"].arrayValue.map { excerptJSON in
                ChatExcerptInput(
                    excerpt: excerptJSON["excerpt"].stringValue,
                    context: excerptJSON["context"].string
                )
            }

            return CardProposal(
                cardId: json["card_id"].stringValue,
                cardType: json["card_type"].stringValue,
                title: json["title"].stringValue,
                timelineEntryId: json["timeline_entry_id"].string,
                assignedArtifactIds: json["assigned_artifact_ids"].arrayValue.map { $0.stringValue },
                chatExcerpts: chatExcerpts,
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

        // Note: Cards are now stored immediately when agents complete (in KnowledgeCardAgentService.runSingleAgent)
        // This fixes the race condition where kcAgentCompleted event arrived before card was stored

        // Build response with handles only (no full card content)
        var response = JSON()
        response["status"].string = "completed"
        response["total_cards"].int = result.cards.count
        response["success_count"].int = result.successCount
        response["failure_count"].int = result.failureCount
        response["duration_seconds"].double = result.totalDuration

        // Return compact card handles (not full content)
        var cardHandles: [[String: Any]] = []
        for card in result.successfulCards {
            let wordCount = card.prose.components(separatedBy: .whitespacesAndNewlines).count
            let shortSummary = String(card.prose.prefix(150)).components(separatedBy: ".").first ?? ""
            cardHandles.append([
                "card_id": card.cardId,
                "title": card.title,
                "word_count": wordCount,
                "short_summary": shortSummary.trimmingCharacters(in: .whitespaces)
            ])
        }
        response["cards"].arrayObject = cardHandles

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

        // Instructions for next steps - cards are auto-presented for validation
        response["instructions"].string = buildInstructions(result: result)

        return .immediate(response)
    }

    private func buildInstructions(result: KCDispatchResult) -> String {
        if result.failureCount == 0 {
            return "All \(result.successCount) cards generated successfully. Cards will be automatically presented for user validation. You will receive developer messages indicating approval/rejection status."
        } else {
            return "\(result.successCount) succeeded, \(result.failureCount) failed. Successful cards will be automatically presented for user validation."
        }
    }
}
