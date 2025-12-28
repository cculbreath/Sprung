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

    // MARK: - Assignment Schema

    /// Schema for a card-to-artifact assignment
    /// Used by: ProposeCardAssignmentsTool
    static let assignmentSchema = JSONSchema(
        type: .object,
        description: "A proposed assignment linking a knowledge card to artifacts",
        properties: [
            "card_id": JSONSchema(
                type: .string,
                description: "Unique UUID for this card"
            ),
            "card_title": JSONSchema(
                type: .string,
                description: "Descriptive title (e.g., 'Senior Engineer at Company X')"
            ),
            "card_type": JSONSchema(
                type: .string,
                description: "Card type: 'job', 'skill', 'project', 'achievement', or 'education'",
                enum: ["job", "skill", "project", "achievement", "education"]
            ),
            "timeline_entry_id": JSONSchema(
                type: .string,
                description: "Optional: ID of the timeline entry this card relates to"
            ),
            "artifact_ids": JSONSchema(
                type: .array,
                description: "Artifact IDs assigned to inform this card",
                items: JSONSchema(type: .string)
            ),
            "notes": JSONSchema(
                type: .string,
                description: "Brief notes explaining why these artifacts were assigned"
            )
        ],
        required: ["card_id", "card_title", "card_type", "artifact_ids"]
    )

    // MARK: - Documentation Gap Schema

    /// Schema for a documentation gap
    /// Used by: ProposeCardAssignmentsTool
    static let gapSchema = JSONSchema(
        type: .object,
        description: "Documentation gap with specific recommendations",
        properties: [
            "card_id": JSONSchema(type: .string, description: "UUID of the card"),
            "card_title": JSONSchema(type: .string, description: "Title of the card"),
            "role_category": JSONSchema(type: .string, description: "Role category: engineering, management, sales, product, design, other"),
            "recommended_doc_types": JSONSchema(
                type: .array,
                description: "Specific doc types to request (e.g., 'performance reviews', 'design docs')",
                items: JSONSchema(type: .string)
            ),
            "example_prompt": JSONSchema(type: .string, description: "Example prompt for the user"),
            "gap_severity": JSONSchema(type: .string, description: "critical, moderate, or minor")
        ],
        required: ["card_id", "card_title", "recommended_doc_types", "example_prompt"]
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

    /// Schema for summary text in propose_card_assignments
    /// Used by: ProposeCardAssignmentsTool
    static let proposalSummary = JSONSchema(
        type: .string,
        description: "Brief summary explaining the assignments and any gaps"
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

    /// Array of card-to-artifact assignments
    /// Used by: ProposeCardAssignmentsTool
    static let assignmentsArray = JSONSchema(
        type: .array,
        description: "Card-to-artifact assignments",
        items: assignmentSchema
    )

    /// Array of documentation gaps
    /// Used by: ProposeCardAssignmentsTool
    static let gapsArray = JSONSchema(
        type: .array,
        description: "Documentation gaps identified (cards without sufficient artifacts)",
        items: gapSchema
    )

    // MARK: - Evidence Block Schema

    /// Evidence block schema for structured knowledge cards
    static let evidenceBlockSchema = JSONSchema(
        type: .object,
        description: "Evidence block from a source document",
        properties: [
            "source_document": JSONSchema(
                type: .string,
                description: "Document ID this evidence comes from"
            ),
            "source_type": JSONSchema(
                type: .string,
                description: "Whether this is primary or supporting evidence",
                enum: ["primary", "supporting"]
            ),
            "locations": JSONSchema(
                type: .array,
                description: "Where in the document this evidence is found",
                items: JSONSchema(type: .string)
            ),
            "extracted_content": JSONSchema(
                type: .object,
                description: "Content extracted from the source",
                properties: [
                    "facts": JSONSchema(
                        type: .array,
                        description: "Facts extracted from this source",
                        items: JSONSchema(type: .string)
                    ),
                    "verbatim_quotes": JSONSchema(
                        type: .array,
                        description: "Direct quotes from the source",
                        items: JSONSchema(type: .string)
                    )
                ],
                required: ["facts"]
            )
        ],
        required: ["source_document", "source_type", "locations", "extracted_content"]
    )

    // MARK: - Structured Card Schema

    /// Schema for structured knowledge card output from KC agents
    static let structuredCardSchema = JSONSchema(
        type: .object,
        description: "Structured knowledge card with evidence blocks",
        properties: [
            "card_id": JSONSchema(type: .string, description: "Unique card identifier"),
            "card_type": JSONSchema(
                type: .string,
                description: "Type of knowledge card",
                enum: ["employment", "project", "skill", "achievement", "education"]
            ),
            "title": JSONSchema(type: .string, description: "Card title"),
            "date_range": JSONSchema(type: .string, description: "Time period covered"),
            "organization": JSONSchema(type: .string, description: "Organization/company name"),
            "location": JSONSchema(type: .string, description: "Geographic location"),
            "evidence_blocks": JSONSchema(
                type: .array,
                description: "Evidence from source documents",
                items: evidenceBlockSchema
            ),
            "facts": JSONSchema(
                type: .object,
                description: "Extracted facts",
                properties: [
                    "scope": JSONSchema(type: .string),
                    "responsibilities": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                    "technologies": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                    "outcomes": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                    "quantified": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                    "context": JSONSchema(type: .string)
                ]
            ),
            "resume_bullets": JSONSchema(
                type: .array,
                description: "Pre-generated resume bullets",
                items: JSONSchema(type: .string)
            ),
            "related_cards": JSONSchema(
                type: .array,
                description: "IDs of related cards",
                items: JSONSchema(type: .string)
            ),
            "keywords": JSONSchema(
                type: .array,
                description: "Keywords for search/matching",
                items: JSONSchema(type: .string)
            ),
            "evidence_quality": JSONSchema(
                type: .string,
                description: "Overall evidence quality",
                enum: ["strong", "moderate", "weak"]
            )
        ],
        required: ["card_id", "card_type", "title", "evidence_blocks", "facts", "resume_bullets"]
    )
}
