//
//  CustomizationSchemas.swift
//  Sprung
//
//  JSONSchema definitions for server-enforced structured output
//  in the resume customization workflow.
//

import Foundation
import SwiftOpenAI

enum CustomizationSchemas {

    // MARK: - Top-Level Schemas

    /// Schema for a single proposed revision to a resume node.
    static var proposedRevisionNode: JSONSchema {
        JSONSchema(
            type: .object,
            description: "A proposed revision to a single resume node",
            properties: [
                "id": JSONSchema(
                    type: .string,
                    description: "Unique identifier of the node being revised"
                ),
                "oldValue": JSONSchema(
                    type: .string,
                    description: "Original text value before revision"
                ),
                "newValue": JSONSchema(
                    type: .string,
                    description: "For scalar nodes: the revised text. For list nodes: a newline-joined summary of newValueArray (secondary to newValueArray)."
                ),
                "valueChanged": JSONSchema(
                    type: .boolean,
                    description: "Whether the value was actually changed"
                ),
                "isTitleNode": JSONSchema(
                    type: .boolean,
                    description: "Whether this is a title/name node rather than content"
                ),
                "why": JSONSchema(
                    type: .string,
                    description: "Explanation of why this revision was made"
                ),
                "treePath": JSONSchema(
                    type: .string,
                    description: "Dot-separated path to this node in the resume tree"
                ),
                "nodeType": JSONSchema(
                    type: .string,
                    description: "Node type: 'list' for array content (keywords, highlights, bullet points) — MUST populate newValueArray. 'scalar' for single text values — set newValueArray to null.",
                    enum: ["scalar", "list"]
                ),
                "oldValueArray": JSONSchema(
                    type: .array,
                    description: "Original array of individual items for list nodes. Empty array [] when nodeType is 'scalar'.",
                    items: JSONSchema(type: .string)
                ),
                "newValueArray": JSONSchema(
                    type: .array,
                    description: "Array of individual items when nodeType is 'list'. Each element is a separate string (e.g., one keyword per element, one bullet per element). Empty array [] when nodeType is 'scalar'.",
                    items: JSONSchema(type: .string)
                )
            ],
            required: [
                "id", "oldValue", "newValue", "valueChanged",
                "isTitleNode", "why", "treePath", "nodeType",
                "oldValueArray", "newValueArray"
            ],
            additionalProperties: false
        )
    }

    /// Schema for a compound revision response containing multiple field revisions.
    static var compoundRevisionResponse: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Response containing multiple field revisions for a compound task",
            properties: [
                "compoundFields": JSONSchema(
                    type: .array,
                    description: "Array of individual field revisions",
                    items: proposedRevisionNode
                )
            ],
            required: ["compoundFields"],
            additionalProperties: false
        )
    }

    /// Schema for the strategic targeting plan that guides all downstream customization.
    static var targetingPlan: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Strategic pre-analysis that establishes the resume narrative for a specific job application",
            properties: [
                "narrativeArc": JSONSchema(
                    type: .string,
                    description: "2-3 sentence overarching story this resume tells for this role"
                ),
                "kcSectionMapping": JSONSchema(
                    type: .array,
                    description: "Knowledge card to resume section assignments",
                    items: kcSectionMappingSchema
                ),
                "emphasisThemes": JSONSchema(
                    type: .array,
                    description: "3-5 themes to emphasize across all sections",
                    items: JSONSchema(type: .string)
                ),
                "workEntryGuidance": JSONSchema(
                    type: .array,
                    description: "Per-entry framing guidance",
                    items: workEntryGuidanceSchema
                ),
                "lateralConnections": JSONSchema(
                    type: .array,
                    description: "Non-obvious skill transfer connections",
                    items: lateralConnectionSchema
                ),
                "prioritizedSkills": JSONSchema(
                    type: .array,
                    description: "Skills ordered by importance for this application",
                    items: JSONSchema(type: .string)
                ),
                "identifiedGaps": JSONSchema(
                    type: .array,
                    description: "Gaps relative to job requirements",
                    items: JSONSchema(type: .string)
                ),
                "kcRelevanceTiers": kcRelevanceTiersSchema
            ],
            required: [
                "narrativeArc", "kcSectionMapping", "emphasisThemes",
                "workEntryGuidance", "lateralConnections", "prioritizedSkills",
                "identifiedGaps", "kcRelevanceTiers"
            ],
            additionalProperties: false
        )
    }

    /// Schema for the post-assembly coherence report.
    static var coherenceReport: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Result of the post-assembly coherence check on the assembled resume",
            properties: [
                "issues": JSONSchema(
                    type: .array,
                    description: "Individual coherence issues detected",
                    items: coherenceIssueSchema
                ),
                "overallCoherence": JSONSchema(
                    type: .string,
                    description: "Overall coherence grade",
                    enum: ["good", "fair", "poor"]
                ),
                "summary": JSONSchema(
                    type: .string,
                    description: "1-2 sentence coherence assessment"
                )
            ],
            required: ["issues", "overallCoherence", "summary"],
            additionalProperties: false
        )
    }

    // MARK: - Private Nested Schemas

    /// Schema for a knowledge card to resume section mapping.
    private static var kcSectionMappingSchema: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Maps a knowledge card to its recommended resume section",
            properties: [
                "cardId": JSONSchema(
                    type: .string,
                    description: "UUID string of the knowledge card"
                ),
                "cardTitle": JSONSchema(
                    type: .string,
                    description: "Human-readable card title"
                ),
                "recommendedSection": JSONSchema(
                    type: .string,
                    description: "Resume section: work, projects, skills, summary, or education"
                ),
                "rationale": JSONSchema(
                    type: .string,
                    description: "Why this card maps to this section"
                )
            ],
            required: ["cardId", "cardTitle", "recommendedSection", "rationale"],
            additionalProperties: false
        )
    }

    /// Schema for per-entry framing guidance.
    private static var workEntryGuidanceSchema: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Framing guidance for a specific work entry",
            properties: [
                "entryIdentifier": JSONSchema(
                    type: .string,
                    description: "Company + role or project name"
                ),
                "leadAngle": JSONSchema(
                    type: .string,
                    description: "Framing angle to lead with"
                ),
                "emphasis": JSONSchema(
                    type: .array,
                    description: "Aspects to highlight",
                    items: JSONSchema(type: .string)
                ),
                "deEmphasis": JSONSchema(
                    type: .array,
                    description: "Aspects to minimize",
                    items: JSONSchema(type: .string)
                ),
                "supportingCardIds": JSONSchema(
                    type: .array,
                    description: "Knowledge card UUIDs providing evidence",
                    items: JSONSchema(type: .string)
                )
            ],
            required: ["entryIdentifier", "leadAngle", "emphasis", "deEmphasis", "supportingCardIds"],
            additionalProperties: false
        )
    }

    /// Schema for a non-obvious skill transfer connection.
    private static var lateralConnectionSchema: JSONSchema {
        JSONSchema(
            type: .object,
            description: "A non-obvious connection between candidate experience and a job requirement",
            properties: [
                "sourceCardId": JSONSchema(
                    type: .string,
                    description: "UUID of source knowledge card"
                ),
                "sourceCardTitle": JSONSchema(
                    type: .string,
                    description: "Title of source card"
                ),
                "targetRequirement": JSONSchema(
                    type: .string,
                    description: "Job requirement this connects to"
                ),
                "reasoning": JSONSchema(
                    type: .string,
                    description: "How the experience transfers"
                )
            ],
            required: ["sourceCardId", "sourceCardTitle", "targetRequirement", "reasoning"],
            additionalProperties: false
        )
    }

    /// Schema for tiered relevance classification of knowledge cards.
    private static var kcRelevanceTiersSchema: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Tiered relevance classification for knowledge cards",
            properties: [
                "primary": JSONSchema(
                    type: .array,
                    description: "Directly relevant card IDs",
                    items: JSONSchema(type: .string)
                ),
                "supporting": JSONSchema(
                    type: .array,
                    description: "Transferable skills card IDs",
                    items: JSONSchema(type: .string)
                ),
                "background": JSONSchema(
                    type: .array,
                    description: "Breadth context card IDs",
                    items: JSONSchema(type: .string)
                )
            ],
            required: ["primary", "supporting", "background"],
            additionalProperties: false
        )
    }

    /// Schema for a single coherence issue.
    private static var coherenceIssueSchema: JSONSchema {
        JSONSchema(
            type: .object,
            description: "A single coherence issue detected in the assembled resume",
            properties: [
                "id": JSONSchema(
                    type: .string,
                    description: "Unique identifier for this issue"
                ),
                "category": JSONSchema(
                    type: .string,
                    description: "Issue category"
                ),
                "severity": JSONSchema(
                    type: .string,
                    description: "Issue severity: high, medium, or low"
                ),
                "description": JSONSchema(
                    type: .string,
                    description: "Plain-language explanation of the problem"
                ),
                "locations": JSONSchema(
                    type: .array,
                    description: "Resume paths involved",
                    items: JSONSchema(type: .string)
                ),
                "suggestion": JSONSchema(
                    type: .string,
                    description: "Recommended fix"
                )
            ],
            required: ["id", "category", "severity", "description", "locations", "suggestion"],
            additionalProperties: false
        )
    }
}
