//
//  SkillsProcessingPrompts.swift
//  Sprung
//
//  Prompt builders and JSON schemas for deduplication and ATS expansion.
//  Pure-function enum namespace — no stored state, no @MainActor, no async.
//

import Foundation

/// Builds prompts and schemas for skills processing operations
enum SkillsProcessingPrompts {

    // MARK: - Deduplication

    /// Build the prompt for deduplication, adjusting for continuation if needed
    static func deduplicationPrompt(
        skills: [String],
        processedSkillIds: Set<String>,
        isFirstPart: Bool,
        partNumber: Int
    ) -> String {
        let skillsList = skills.joined(separator: "\n")

        if isFirstPart {
            return """
            Analyze the following \(skills.count) skills and identify groups of duplicates that should be merged.

            Skills (format: "uuid: name [category]"):
            \(skillsList)

            Identify skills that are semantically the same but may have:
            - Different casing (e.g., "python" vs "Python")
            - Different formatting (e.g., "JavaScript" vs "Javascript" vs "JS")
            - Abbreviations vs full names (e.g., "ML" vs "Machine Learning")
            - Version numbers that don't matter (e.g., "Python 3" vs "Python")
            - Synonyms in professional context (e.g., "React.js" vs "ReactJS")

            For each duplicate group, provide:
            - The canonical (best) name to use
            - All skill IDs that should be merged into one
            - Brief reasoning for the merge

            IMPORTANT:
            - Only include actual duplicates - skills with similar but distinct meanings should NOT be grouped
            - "AWS" and "Azure" are NOT duplicates (different platforms)
            - "React" and "React Native" are NOT duplicates (different frameworks)
            - "Python" and "Python 3" ARE duplicates (same language)
            - If no duplicates are found, return an empty duplicateGroups array

            OUTPUT BATCHING (critical):
            - Process at most 100 skills per response to avoid output truncation
            - Set "hasMore" to true if you haven't finished analyzing all skills
            - Set "hasMore" to false only when you've checked ALL skills for duplicates
            - Include all skill IDs you've processed (checked for duplicates) in "processedSkillIds"
            - Skills not in any duplicate group should still be listed in processedSkillIds if you've checked them
            """
        } else {
            let alreadyProcessed = processedSkillIds.joined(separator: ", ")
            let remainingCount = skills.count - processedSkillIds.count
            return """
            CONTINUATION (Part \(partNumber)) - Continue analyzing the same skill list for duplicates.
            Approximately \(remainingCount) skills remaining to process.

            Skills (format: "uuid: name [category]"):
            \(skillsList)

            ALREADY PROCESSED SKILL IDs (skip these - \(processedSkillIds.count) total):
            \(alreadyProcessed)

            Continue identifying duplicate groups from the remaining skills. Do NOT re-report duplicates involving the already-processed IDs.

            OUTPUT BATCHING (critical):
            - Process at most 100 NEW skills per response
            - Set "hasMore" to true if you haven't finished analyzing all remaining skills
            - Set "hasMore" to false only when you've checked ALL remaining skills
            - Include all NEW skill IDs you've processed in "processedSkillIds"
            - Skills not in any duplicate group should still be listed in processedSkillIds if you've checked them
            """
        }
    }

    /// Schema for deduplication response with multi-part support
    static var deduplicationSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "duplicateGroups": [
                    "type": "array",
                    "description": "Groups of duplicate skills to merge",
                    "items": [
                        "type": "object",
                        "properties": [
                            "canonicalName": [
                                "type": "string",
                                "description": "The best canonical name to use for this skill"
                            ],
                            "skillIds": [
                                "type": "array",
                                "description": "UUIDs of all skills in this duplicate group",
                                "items": ["type": "string"]
                            ],
                            "reasoning": [
                                "type": "string",
                                "description": "Brief explanation of why these are duplicates"
                            ]
                        ],
                        "required": ["canonicalName", "skillIds", "reasoning"]
                    ]
                ],
                "hasMore": [
                    "type": "boolean",
                    "description": "Set to true if there are more duplicate groups that couldn't fit in this response. Set false when done."
                ],
                "processedSkillIds": [
                    "type": "array",
                    "description": "IDs of all skills included in duplicate groups in THIS response",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["duplicateGroups", "hasMore", "processedSkillIds"]
        ]
    }

    // MARK: - ATS Batch Expansion

    /// Build prompt for batch ATS synonym expansion
    static func atsBatchPrompt(skillDescriptions: [String]) -> String {
        """
        For each skill below, generate ATS (Applicant Tracking System) synonym variants.

        Skills (format: "uuid: name (existing variants if any)"):
        \(skillDescriptions.joined(separator: "\n"))

        For each skill, generate variants that ATS systems commonly recognize, including:
        - Alternative spellings (e.g., "Javascript" → ["JavaScript", "JS"])
        - Abbreviations and acronyms (e.g., "Machine Learning" → ["ML"])
        - Full forms of abbreviations (e.g., "SQL" → ["Structured Query Language"])
        - Common misspellings that ATS should match
        - Version-agnostic forms (e.g., "Python 3.9" → ["Python", "Python 3"])
        - Framework/library associations (e.g., "React" → ["React.js", "ReactJS"])
        - Professional synonyms (e.g., "Agile" → ["Agile Methodology", "Scrum", "Kanban"])

        Guidelines:
        - Generate 3-8 variants per skill
        - Don't duplicate existing variants
        - Include the most common ATS variations
        - Focus on variants that actually appear in job postings
        - Don't include unrelated skills as variants
        """
    }

    /// Schema for batch ATS expansion response
    static var atsExpansionSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "skills": [
                    "type": "array",
                    "description": "ATS variants for each skill",
                    "items": [
                        "type": "object",
                        "properties": [
                            "skillId": [
                                "type": "string",
                                "description": "UUID of the skill"
                            ],
                            "variants": [
                                "type": "array",
                                "description": "ATS synonym variants",
                                "items": ["type": "string"]
                            ]
                        ],
                        "required": ["skillId", "variants"]
                    ]
                ]
            ],
            "required": ["skills"]
        ]
    }

    // MARK: - Single-Skill ATS

    /// Build prompt for single-skill ATS variant generation
    static func singleSkillATSPrompt(canonical: String, category: String) -> String {
        """
        Generate ATS (Applicant Tracking System) synonym variants for this skill:

        Skill: \(canonical)
        Category: \(category)

        Generate variants that ATS systems commonly recognize, including:
        - Alternative spellings (e.g., "Javascript" → ["JavaScript", "JS"])
        - Abbreviations and acronyms (e.g., "Machine Learning" → ["ML"])
        - Full forms of abbreviations (e.g., "SQL" → ["Structured Query Language"])
        - Common misspellings that ATS should match
        - Version-agnostic forms (e.g., "Python 3.9" → ["Python", "Python 3"])
        - Framework/library associations (e.g., "React" → ["React.js", "ReactJS"])
        - Professional synonyms (e.g., "Agile" → ["Agile Methodology", "Scrum", "Kanban"])

        Guidelines:
        - Generate 3-8 variants
        - Include the most common ATS variations
        - Focus on variants that actually appear in job postings
        - Don't include unrelated skills as variants
        """
    }

    /// Schema for single-skill ATS variant response
    static var singleSkillATSSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "variants": [
                    "type": "array",
                    "description": "ATS synonym variants for the skill",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["variants"]
        ]
    }
}
