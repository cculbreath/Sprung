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
            "documentType": [
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
                        "cardType": [
                            "type": "string",
                            "enum": ["employment", "project", "skill", "achievement", "education"],
                            "description": "Type of card: skill (for technologies/tools), project (for the repo or sub-projects), achievement (for notable accomplishments)"
                        ],
                        "proposedTitle": [
                            "type": "string",
                            "description": "Specific, descriptive title (e.g., 'SwiftUI Application Architecture' not just 'Swift')"
                        ],
                        "evidenceStrength": [
                            "type": "string",
                            "enum": ["primary", "supporting", "mention"],
                            "description": "primary: main source of evidence, supporting: adds detail, mention: brief reference"
                        ],
                        "evidenceLocations": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "File paths where evidence was found (e.g., 'src/services/AuthService.swift:45-120')"
                        ],
                        "keyFacts": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Specific facts extracted: patterns used, complexity handled, problems solved. Be detailed."
                        ],
                        "technologies": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "All technologies, frameworks, tools, libraries demonstrated"
                        ],
                        "quantifiedOutcomes": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Any quantifiable metrics: lines of code, test coverage, performance numbers, scale indicators"
                        ],
                        "dateRange": [
                            "type": "string",
                            "description": "Date range if determinable from git history (e.g., '2023-2024')"
                        ],
                        "crossReferences": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Titles of related cards (e.g., a project card referencing skill cards for technologies used)"
                        ],
                        "extractionNotes": [
                            "type": "string",
                            "description": "Notes about evidence quality, gaps, or recommendations for this card"
                        ]
                    ],
                    "required": ["cardType", "proposedTitle", "evidenceStrength", "evidenceLocations", "keyFacts", "technologies", "quantifiedOutcomes", "crossReferences"]
                ]
            ]
        ],
        "required": ["documentType", "cards"],
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
    }

    struct Parameters: Codable {
        let documentType: String
        let cards: [ProposedCard]
    }
}
