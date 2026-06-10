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
        Provide a card inventory of well-evidenced knowledge cards from the codebase.
        Each card must have specific evidence from files you examined — include a skill only if the \
        evidence would survive an interviewer asking "tell me about a time you used X".
        Card types: skill (technologies/tools/techniques), project (the repo itself or sub-projects), achievement (notable accomplishments).
        Skill cards MUST set proficiency, category, and atsVariants.
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
                "description": "Well-evidenced knowledge cards identified from the repository. Prefer 15-35 defensible cards over a long undifferentiated list.",
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
                            "description": "Metrics only when the number means something to an outsider: scale served, performance achieved, duration sustained. Do NOT include lines of code or file counts."
                        ],
                        "proficiency": [
                            "type": "string",
                            "enum": ["expert", "proficient", "familiar"],
                            "description": "REQUIRED for skill cards. Proficiency per the evidence rubric, grounded in the longitudinal git evidence (tenure in the area, sustained activity). Rubric assessments at Competent level map to 'familiar'."
                        ],
                        "category": [
                            "type": "string",
                            "description": "REQUIRED for skill cards. Skill-bank category: use the universal anchors (Tools & Software, Leadership & Management, Communication & Writing, Methodologies & Processes) plus domain-appropriate categories you propose (e.g., Programming Languages, Frameworks & Libraries, Scientific & Analysis)."
                        ],
                        "atsVariants": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "For skill cards: search-term variants of THIS skill's name that an employer might use (e.g., 'Python' -> ['python3', 'Python programming']). NOT the technology list."
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

    /// Matches DocumentInventory.ProposedCardEntry for unified pipeline,
    /// plus skill-card judgment fields (proficiency, category, atsVariants).
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
        /// Skill cards only: expert | proficient | familiar
        let proficiency: String?
        /// Skill cards only: skill-bank category (universal anchors + domain categories)
        let category: String?
        /// Skill cards only: search-term variants of the skill's name
        let atsVariants: [String]?
    }

    struct Parameters: Codable {
        let documentType: String
        let cards: [ProposedCard]
    }
}
