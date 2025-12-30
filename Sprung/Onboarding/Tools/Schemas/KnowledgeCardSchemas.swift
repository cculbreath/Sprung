//
//  KnowledgeCardSchemas.swift
//  Sprung
//
//  Shared JSON schema definitions for Knowledge Card related tools.
//  DRY: Used by DisplayKnowledgeCardPlanTool, DispatchKCAgentsTool, ProposeCardAssignmentsTool,
//       SubmitKnowledgeCardTool, and SetCurrentKnowledgeCardTool.
//
import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Shared schema definitions for Knowledge Card fields
enum KnowledgeCardSchemas {
    // MARK: - Plan Item Schema

    /// Schema for a knowledge card plan item
    /// Used by: DisplayKnowledgeCardPlanTool
    static let planItemSchema = JSONSchema(
        type: .object,
        description: "A planned knowledge card item",
        properties: [
            "id": JSONSchema(type: .string, description: "Unique identifier for this item"),
            "title": JSONSchema(type: .string, description: "Title of the knowledge card (e.g., job title or skill area)"),
            "type": JSONSchema(
                type: .string,
                description: "Type of card: 'job' for positions, 'skill' for skill areas, 'project', 'achievement', or 'education'",
                enum: ["job", "skill", "project", "achievement", "education"]
            ),
            "description": JSONSchema(type: .string, description: "Brief description of what this card will cover"),
            "status": JSONSchema(
                type: .string,
                description: "Current status of this item",
                enum: ["pending", "in_progress", "completed", "skipped"]
            ),
            "timeline_entry_id": JSONSchema(type: .string, description: "Optional: ID of the related timeline entry")
        ],
        required: ["id", "title", "type", "status"],
        additionalProperties: false
    )

    // MARK: - Chat Excerpt Input Schema

    /// Schema for a chat excerpt to include as source material
    /// Used by: DispatchKCAgentsTool, ProposeCardAssignmentsTool
    static let chatExcerptInputSchema = JSONSchema(
        type: .object,
        description: "A conversation excerpt to include as source material for a knowledge card",
        properties: [
            "excerpt": JSONSchema(
                type: .string,
                description: "The quoted text from the conversation (user's exact words)"
            ),
            "context": JSONSchema(
                type: .string,
                description: "Brief context explaining what this excerpt demonstrates or why it's relevant"
            )
        ],
        required: ["excerpt"]
    )

    // MARK: - Card Proposal Schema

    /// Schema for a card proposal (used in dispatch workflow)
    /// Used by: DispatchKCAgentsTool, ProposeCardAssignmentsTool
    static let cardProposalSchema = JSONSchema(
        type: .object,
        properties: [
            "card_id": JSONSchema(
                type: .string,
                description: "Unique ID for this card (UUID)"
            ),
            "card_type": JSONSchema(
                type: .string,
                description: "Type of card: 'job', 'skill', 'project', 'achievement', or 'education'",
                enum: ["job", "skill", "project", "achievement", "education"]
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
            "chat_excerpts": JSONSchema(
                type: .array,
                description: "Conversation excerpts as source material (for verbally shared info)",
                items: chatExcerptInputSchema
            ),
            "notes": JSONSchema(
                type: .string,
                description: "Optional notes for the KC agent about this card"
            )
        ],
        required: ["card_id", "card_type", "title"]
    )


    // MARK: - Source Schema

    /// Schema for a knowledge card source reference
    /// Used by: SubmitKnowledgeCardTool
    static let sourceSchema = JSONSchema(
        type: .object,
        description: "Source reference linking card to evidence",
        properties: [
            "type": JSONSchema(type: .string, description: "Source type", enum: ["artifact", "chat"]),
            "artifact_id": JSONSchema(type: .string, description: "Artifact UUID (required for type=artifact)"),
            "chat_excerpt": JSONSchema(type: .string, description: "Quoted text (required for type=chat)"),
            "chat_context": JSONSchema(type: .string, description: "Context for the excerpt")
        ],
        required: ["type"]
    )

    // MARK: - Full Card Schema

    /// Schema for a complete knowledge card with content and sources
    /// Used by: SubmitKnowledgeCardTool
    static let cardSchema = JSONSchema(
        type: .object,
        description: "Knowledge card with comprehensive prose content (500-2000+ words) and sources",
        properties: [
            "id": JSONSchema(type: .string, description: "Unique UUID"),
            "title": JSONSchema(type: .string, description: "Descriptive title (e.g., 'Senior Engineer at Acme (2020-2024)')"),
            "type": JSONSchema(type: .string, description: "Category: job, skill, education, or project"),
            "content": JSONSchema(type: .string, description: "Comprehensive prose (500-2000+ words). Include all details: projects, achievements, metrics, skills."),
            "sources": JSONSchema(type: .array, description: "Evidence sources (at least one required)", items: sourceSchema),
            "time_period": JSONSchema(type: .string, description: "Date range (e.g., '2020-09 to 2024-06')"),
            "organization": JSONSchema(type: .string, description: "Company/organization name"),
            "location": JSONSchema(type: .string, description: "Location or 'Remote'")
        ],
        required: ["id", "title", "content", "sources"],
        additionalProperties: true
    )

    // MARK: - Common Field Schemas

    /// Schema for plan item ID
    /// Used by: SetCurrentKnowledgeCardTool
    static let itemId = JSONSchema(
        type: .string,
        description: "The ID of the plan item to mark as current (must match an ID from display_knowledge_card_plan)"
    )

    /// Schema for current focus (plan item ID)
    /// Used by: DisplayKnowledgeCardPlanTool
    static let currentFocus = JSONSchema(
        type: .string,
        description: "ID of the item currently being worked on (for highlighting)"
    )

    /// Schema for optional message to display
    /// Used by: DisplayKnowledgeCardPlanTool, SetCurrentKnowledgeCardTool
    static let message = JSONSchema(
        type: .string,
        description: "Optional message to display (e.g., 'Let's start with your role at Company X')"
    )

    /// Schema for summary text in submit_knowledge_card
    /// Used by: SubmitKnowledgeCardTool
    static let submissionSummary = JSONSchema(
        type: .string,
        description: "Brief summary for the approval UI (e.g., 'Knowledge card for your 5 years at Acme Corp with 8 achievements')"
    )

    // MARK: - Array Wrapper Schemas

    /// Array of plan items
    /// Used by: DisplayKnowledgeCardPlanTool
    static let planItemsArray = JSONSchema(
        type: .array,
        description: "The complete list of planned knowledge cards with current status",
        items: planItemSchema
    )

    /// Array of card proposals
    /// Used by: DispatchKCAgentsTool
    static let proposalsArray = JSONSchema(
        type: .array,
        description: "Card proposals to process in parallel",
        items: cardProposalSchema
    )

}
