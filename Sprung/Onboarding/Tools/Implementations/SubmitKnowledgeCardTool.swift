//
//  SubmitKnowledgeCardTool.swift
//  Sprung
//
//  Submits a knowledge card for user approval and auto-persists on confirmation.
//  This is the culmination of the Phase 2 knowledge card workflow.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Tool that submits a knowledge card for user approval.
///
/// PHASE 2 WORKFLOW:
/// 1. `display_knowledge_card_plan` - Shows all cards to create (plan items)
/// 2. `set_current_knowledge_card` - Focus on one plan item
/// 3. (Collect evidence: documents, git repos, conversation)
/// 4. **`submit_knowledge_card`** - Submit the card for approval → auto-persists on confirm
/// 5. Repeat steps 2-4 for each plan item
///
/// This tool combines validation, approval, and persistence to ensure cards are properly saved.
struct SubmitKnowledgeCardTool: InterviewTool {
    private static let schema = JSONSchema(
        type: .object,
        description: """
            Submit a knowledge card for user approval. Provide EITHER card_id (from dispatch_kc_agents) \
            OR full card object. Card is validated, presented for approval, and auto-persisted on confirm.
            """,
        properties: [
            "card_id": JSONSchema(
                type: .string,
                description: "ID of a pending card from dispatch_kc_agents. Use this instead of 'card' when available."
            ),
            "card": KnowledgeCardSchemas.cardSchema,
            "summary": KnowledgeCardSchemas.submissionSummary
        ],
        required: ["summary"],
        additionalProperties: false
    )

    private unowned let coordinator: OnboardingInterviewCoordinator
    private let dataStore: InterviewDataStore
    private let eventBus: EventCoordinator

    init(coordinator: OnboardingInterviewCoordinator, dataStore: InterviewDataStore, eventBus: EventCoordinator) {
        self.coordinator = coordinator
        self.dataStore = dataStore
        self.eventBus = eventBus
    }

    var name: String { OnboardingToolName.submitKnowledgeCard.rawValue }
    var description: String {
        """
        Submit a knowledge card for user approval. \
        Validates sources, presents for approval, auto-persists on confirm. \
        Call after collecting evidence for the current plan item.
        """
    }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Check if batch upload is in progress - reject to prevent interrupting uploads
        let hasBatchInProgress = await MainActor.run { coordinator.ui.hasBatchUploadInProgress }
        if hasBatchInProgress {
            return ToolResultHelpers.executionFailed(
                "Cannot submit knowledge card while document uploads are in progress. " +
                "Wait for the user to finish uploading evidence documents and click 'Done with this card' before resubmitting."
            )
        }

        // Resolve card: prefer card_id (from pending storage), fall back to full card object
        let card: JSON
        let pendingCardId = params["card_id"].string

        if let cardId = pendingCardId {
            // Retrieve from pending storage (Milestone 7: KC content not in main thread)
            guard let pendingCard = await coordinator.state.getPendingCard(id: cardId) else {
                return ToolResultHelpers.invalidParameters(
                    "No pending card found for card_id '\(cardId)'. " +
                    "Ensure dispatch_kc_agents was called and the card_id matches a successful result."
                )
            }
            card = pendingCard
            Logger.info("📦 Retrieved pending card: \(cardId)", category: .ai)
        } else if params["card"] != .null {
            card = params["card"]
        } else {
            return ToolResultHelpers.invalidParameters(
                "Either 'card_id' (preferred) or 'card' object is required. " +
                "Use card_id from dispatch_kc_agents results when available."
            )
        }

        // Validate required fields using helpers
        let cardId: String
        let title: String
        let content: String
        let sources: [JSON]
        let summary: String

        do {
            cardId = try ToolResultHelpers.requireString(card["id"].string, named: "card.id")
            title = try ToolResultHelpers.requireString(card["title"].string, named: "card.title")

            // Validate prose content
            content = try ToolResultHelpers.requireString(card["content"].string, named: "card.content")

            // Check minimum content length (roughly 500 words = ~3000 characters)
            if content.count < 1000 {
                throw ToolError.invalidParameters(
                    "card.content is too short (\(content.count) characters). " +
                    "Knowledge cards must be comprehensive prose summaries (500-2000+ words, ~3000+ characters minimum). " +
                    "Include ALL relevant details - this will replace the source documents for resume generation."
                )
            }

            // Validate sources with custom error message
            guard let sourcesArray = card["sources"].array, !sourcesArray.isEmpty else {
                throw ToolError.invalidParameters(
                    "card.sources is REQUIRED and must contain at least one source. " +
                    "Every knowledge card must be backed by evidence. " +
                    "Use list_artifacts to get artifact IDs, or quote specific chat excerpts."
                )
            }
            sources = sourcesArray

            // Extract summary
            summary = try ToolResultHelpers.requireString(params["summary"].string, named: "summary")
        } catch {
            return .error(error as! ToolError)
        }

        // Validate each source has required fields based on type
        for (index, source) in sources.enumerated() {
            guard let sourceType = source["type"].string else {
                return ToolResultHelpers.invalidParameters("sources[\(index)].type is required ('artifact' or 'chat')")
            }

            switch sourceType {
            case "artifact":
                guard let artifactId = source["artifact_id"].string, !artifactId.isEmpty else {
                    return ToolResultHelpers.invalidParameters(
                        "sources[\(index)].artifact_id is required for artifact sources. " +
                        "Call list_artifacts to get available artifact IDs."
                    )
                }
            case "chat":
                guard let excerpt = source["chat_excerpt"].string, !excerpt.isEmpty else {
                    return ToolResultHelpers.invalidParameters(
                        "sources[\(index)].chat_excerpt is required for chat sources. " +
                        "Quote the exact user statement from the conversation."
                    )
                }
            default:
                return ToolResultHelpers.invalidParameters(
                    "sources[\(index)].type must be 'artifact' or 'chat', got '\(sourceType)'"
                )
            }
        }

        // Get the current plan item focus (if any)
        let planItemId = await MainActor.run { coordinator.getCurrentPlanItemFocus() }

        // Build the card with plan item linkage
        var linkedCard = card
        if let planItemId = planItemId {
            linkedCard["plan_item_id"].string = planItemId
            Logger.info("🔗 Linking knowledge card to plan item: \(planItemId)", category: .ai)
        }

        // Emit event for pending card storage (handler will store it)
        await eventBus.publish(.knowledgeCardSubmissionPending(card: linkedCard))

        // Remove from pending storage if it came from there (Milestone 7)
        // Card data is now in the event handler; no longer needed in pending storage
        if let inputCardId = pendingCardId {
            await coordinator.state.removePendingCard(id: inputCardId)
        }

        // Present validation UI
        let prompt = OnboardingValidationPrompt(
            dataType: "knowledge_card",
            payload: linkedCard,
            message: summary
        )
        await eventBus.publish(.validationPromptRequested(prompt: prompt))

        // NOTE: We do NOT re-gate submit_knowledge_card here.
        // This allows the LLM to submit multiple cards from the same evidence batch.
        // Re-gating happens when set_current_knowledge_card is called for a DIFFERENT item.

        // Build response
        // Note: Use "card_status" not "status" - the API intercepts "status" for tool call status
        var response = JSON()
        response["card_status"].string = "awaiting_confirmation"
        response["card_id"].string = cardId
        response["card_title"].string = title
        response["source_count"].int = sources.count
        if let planItemId = planItemId {
            response["linked_plan_item"].string = planItemId
        }
        response["message"].string = "Card submitted for approval. Auto-persists on confirm."
        response["next_action"].string = "Wait for user response. On reject, revise and resubmit."

        return .immediate(response)
    }
}
