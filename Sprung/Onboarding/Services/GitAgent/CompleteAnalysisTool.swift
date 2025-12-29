//
//  CompleteAnalysisTool.swift
//  Sprung
//
//  Tool for submitting git repository analysis as a card inventory.
//  Output format matches DocumentInventory for unified card pipeline.
//

import Foundation

// MARK: - Complete Analysis Tool

struct CompleteAnalysisTool: AgentTool {
    static let name = "complete_analysis"
    static let description = """
        Call this tool when you have finished analyzing the repository and are ready to submit your findings.
        Provide a card inventory identifying all potential knowledge cards from the codebase.
        Each card should have specific evidence from files you examined.
        Card types: skill (technologies/tools), project (the repo itself or sub-projects), achievement (notable accomplishments).
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "document_type": [
                "type": "string",
                "description": "Always 'git_analysis' for repository analysis",
                "enum": ["git_analysis"]
            ],
            "cards": [
                "type": "array",
                "description": "All potential knowledge cards identified from the repository. Include 10-30 cards for substantial projects.",
                "items": [
                    "type": "object",
                    "properties": [
                        "card_type": [
                            "type": "string",
                            "enum": ["employment", "project", "skill", "achievement", "education"],
                            "description": "Type of card: skill (for technologies/tools), project (for the repo or sub-projects), achievement (for notable accomplishments)"
                        ],
                        "proposed_title": [
                            "type": "string",
                            "description": "Specific, descriptive title (e.g., 'SwiftUI Application Architecture' not just 'Swift')"
                        ],
                        "evidence_strength": [
                            "type": "string",
                            "enum": ["primary", "supporting", "mention"],
                            "description": "primary: main source of evidence, supporting: adds detail, mention: brief reference"
                        ],
                        "evidence_locations": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "File paths where evidence was found (e.g., 'src/services/AuthService.swift:45-120')"
                        ],
                        "key_facts": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Specific facts extracted: patterns used, complexity handled, problems solved. Be detailed."
                        ],
                        "technologies": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "All technologies, frameworks, tools, libraries demonstrated"
                        ],
                        "quantified_outcomes": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Any quantifiable metrics: lines of code, test coverage, performance numbers, scale indicators"
                        ],
                        "date_range": [
                            "type": "string",
                            "description": "Date range if determinable from git history (e.g., '2023-2024')"
                        ],
                        "cross_references": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Titles of related cards (e.g., a project card referencing skill cards for technologies used)"
                        ],
                        "extraction_notes": [
                            "type": "string",
                            "description": "Notes about evidence quality, gaps, or recommendations for this card"
                        ]
                    ],
                    "required": ["card_type", "proposed_title", "evidence_strength", "evidence_locations", "key_facts", "technologies", "quantified_outcomes", "cross_references"]
                ]
            ]
        ],
        "required": ["document_type", "cards"],
        "additionalProperties": false
    ]

    // MARK: - Parameter Types for Decoding

    /// Matches DocumentInventory.ProposedCardEntry for unified pipeline
    struct ProposedCard: Codable {
        let cardType: String
        let proposedTitle: String
        let evidenceStrength: String
        let evidenceLocations: [String]
        let keyFacts: [String]
        let technologies: [String]
        let quantifiedOutcomes: [String]
        let dateRange: String?
        let crossReferences: [String]
        let extractionNotes: String?

        enum CodingKeys: String, CodingKey {
            case cardType = "card_type"
            case proposedTitle = "proposed_title"
            case evidenceStrength = "evidence_strength"
            case evidenceLocations = "evidence_locations"
            case keyFacts = "key_facts"
            case technologies
            case quantifiedOutcomes = "quantified_outcomes"
            case dateRange = "date_range"
            case crossReferences = "cross_references"
            case extractionNotes = "extraction_notes"
        }
    }

    struct Parameters: Codable {
        let documentType: String
        let cards: [ProposedCard]

        enum CodingKeys: String, CodingKey {
            case documentType = "document_type"
            case cards
        }
    }
}
