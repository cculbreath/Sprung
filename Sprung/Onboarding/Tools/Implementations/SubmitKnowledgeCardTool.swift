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
    private static let sourceSchema = JSONSchema(
        type: .object,
        description: """
            A source reference linking the knowledge card to evidence.
            Every card MUST have at least one source to ensure claims are backed by evidence.
            """,
        properties: [
            "type": JSONSchema(
                type: .string,
                description: "Source type: 'artifact' for uploaded documents/repos, 'chat' for conversation quotes",
                enum: ["artifact", "chat"]
            ),
            "artifact_id": JSONSchema(
                type: .string,
                description: "UUID of the artifact (REQUIRED when type='artifact'). Get IDs from list_artifacts."
            ),
            "chat_excerpt": JSONSchema(
                type: .string,
                description: "Quoted text from conversation (REQUIRED when type='chat'). Include the exact user statement."
            ),
            "chat_context": JSONSchema(
                type: .string,
                description: "Brief context explaining what the chat excerpt demonstrates"
            )
        ],
        required: ["type"]
    )

    private static let cardSchema = JSONSchema(
        type: .object,
        description: """
            A knowledge card containing a COMPREHENSIVE PROSE SUMMARY.

            The content field should be a detailed narrative (500-2000+ words) that captures
            EVERYTHING relevant about this experience. This prose will be the PRIMARY SOURCE
            for resume customization and cover letter writing - the original documents will
            NOT be re-read at that time.

            Write as if creating a detailed portfolio entry or comprehensive briefing document.
            """,
        properties: [
            "id": JSONSchema(
                type: .string,
                description: "Unique UUID for this card (generate one)"
            ),
            "title": JSONSchema(
                type: .string,
                description: "Descriptive title (e.g., 'Senior Software Engineer at Acme Corp (2020-2024)')"
            ),
            "type": JSONSchema(
                type: .string,
                description: "Category: 'job', 'skill', 'education', 'project'. Helps with organization."
            ),
            "content": JSONSchema(
                type: .string,
                description: """
                    COMPREHENSIVE PROSE SUMMARY (500-2000+ words).

                    This narrative must capture ALL important details from the source documents:
                    - Role scope, responsibilities, and context
                    - Specific projects with technical details and your contributions
                    - Quantified achievements and business impact
                    - Technologies, tools, and methodologies used
                    - Team dynamics, leadership, collaboration patterns
                    - Challenges overcome and problems solved
                    - Skills demonstrated (technical and soft)

                    Write in third person. Be specific and detailed. Include numbers, metrics,
                    and concrete examples. This document will be used to generate tailored
                    resume bullets and cover letter content for various job applications.

                    DO NOT summarize or compress - PRESERVE all relevant detail from sources.
                    """
            ),
            "sources": JSONSchema(
                type: .array,
                description: "Evidence sources backing this card. AT LEAST ONE REQUIRED.",
                items: sourceSchema
            ),
            "time_period": JSONSchema(
                type: .string,
                description: "Date range if applicable (e.g., '2020-09 to 2024-06', 'Summer 2019')"
            ),
            "organization": JSONSchema(
                type: .string,
                description: "Company, university, or organization name"
            ),
            "location": JSONSchema(
                type: .string,
                description: "Location if relevant (city, state, or 'Remote')"
            )
        ],
        required: ["id", "title", "content", "sources"],
        additionalProperties: true
    )

    private static let schema = JSONSchema(
        type: .object,
        description: """
            SUBMIT A KNOWLEDGE CARD for user approval.

            WHEN TO CALL:
            After collecting evidence for the current plan item (set via set_current_knowledge_card),
            call this tool to submit the completed knowledge card for user approval.

            BEFORE CALLING, VERIFY:
            - All required fields (id, title, content, sources) are populated
            - At least one source is linked (artifact or chat)
            - Content is comprehensive (500+ words for substantial roles)

            WHAT HAPPENS:
            1. Tool validates the card (sources are REQUIRED)
            2. Tool links the card to the current plan item
            3. Tool presents the card for user approval in the Tool Pane
            4. If user CONFIRMS: Card is AUTO-PERSISTED, plan item marked "completed"
            5. If user REJECTS: You receive their feedback to revise and resubmit

            WHAT YOU RECEIVE:
            - Immediately: { status: "awaiting_confirmation", ... }
            - After user confirms: "Knowledge card persisted: [title]. Plan item marked complete."
            - After user rejects: Their feedback. Revise and call submit_knowledge_card again.

            AFTER CONFIRMATION:
            - Call set_current_knowledge_card for the next pending plan item
            - Or call display_knowledge_card_plan to see progress
            - Repeat until all plan items are complete

            SOURCES ARE MANDATORY:
            Every card MUST link to at least one source. Use:
            - list_artifacts to get IDs of uploaded documents
            - Quote specific user statements as chat sources
            """,
        properties: [
            "card": cardSchema,
            "summary": JSONSchema(
                type: .string,
                description: "Brief summary for the approval UI (e.g., 'Knowledge card for your 5 years at Acme Corp with 8 achievements')"
            )
        ],
        required: ["card", "summary"],
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
            return .error(.executionFailed(
                "Cannot submit knowledge card while document uploads are in progress. " +
                "Wait for the user to finish uploading evidence documents and click 'Done with this card' before resubmitting."
            ))
        }

        // Extract and validate card
        let card = params["card"]
        guard card != .null else {
            return .error(.invalidParameters("card is required"))
        }

        // Validate required fields
        guard let cardId = card["id"].string, !cardId.isEmpty else {
            return .error(.invalidParameters("card.id is required (use a UUID)"))
        }

        guard let title = card["title"].string, !title.isEmpty else {
            return .error(.invalidParameters("card.title is required"))
        }

        // Validate prose content
        guard let content = card["content"].string, !content.isEmpty else {
            return .error(.invalidParameters(
                "card.content is REQUIRED and must be a comprehensive prose summary (500-2000+ words). " +
                "This narrative will be the primary source for resume customization."
            ))
        }

        // Check minimum content length (roughly 500 words = ~3000 characters)
        if content.count < 1000 {
            return .error(.invalidParameters(
                "card.content is too short (\(content.count) characters). " +
                "Knowledge cards must be comprehensive prose summaries (500-2000+ words, ~3000+ characters minimum). " +
                "Include ALL relevant details - this will replace the source documents for resume generation."
            ))
        }

        // Validate sources
        guard let sources = card["sources"].array, !sources.isEmpty else {
            return .error(.invalidParameters(
                "card.sources is REQUIRED and must contain at least one source. " +
                "Every knowledge card must be backed by evidence. " +
                "Use list_artifacts to get artifact IDs, or quote specific chat excerpts."
            ))
        }

        // Validate each source has required fields based on type
        for (index, source) in sources.enumerated() {
            guard let sourceType = source["type"].string else {
                return .error(.invalidParameters("sources[\(index)].type is required ('artifact' or 'chat')"))
            }

            switch sourceType {
            case "artifact":
                guard let artifactId = source["artifact_id"].string, !artifactId.isEmpty else {
                    return .error(.invalidParameters(
                        "sources[\(index)].artifact_id is required for artifact sources. " +
                        "Call list_artifacts to get available artifact IDs."
                    ))
                }
            case "chat":
                guard let excerpt = source["chat_excerpt"].string, !excerpt.isEmpty else {
                    return .error(.invalidParameters(
                        "sources[\(index)].chat_excerpt is required for chat sources. " +
                        "Quote the exact user statement from the conversation."
                    ))
                }
            default:
                return .error(.invalidParameters(
                    "sources[\(index)].type must be 'artifact' or 'chat', got '\(sourceType)'"
                ))
            }
        }

        // Extract summary
        guard let summary = params["summary"].string, !summary.isEmpty else {
            return .error(.invalidParameters("summary is required for the approval UI"))
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
        response["message"].string = """
            Knowledge card submitted for user approval.
            When user confirms, the card will be automatically persisted and the plan updated.
            """
        response["next_action"].string = """
            WAIT for user response.
            - If CONFIRMED: Card auto-persisted, plan item marked complete.
            - If REJECTED: User provides feedback. Revise the card and call submit_knowledge_card again.

            If this evidence supports MULTIPLE cards (e.g., a job AND a notable project), you may call \
            submit_knowledge_card again immediately for the additional card(s) - no need to wait for "Done" again.
            """

        return .immediate(response)
    }
}
