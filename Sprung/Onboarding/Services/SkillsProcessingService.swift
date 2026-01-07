//
//  SkillsProcessingService.swift
//  Sprung
//
//  LLM-powered skills processing service for deduplication and ATS synonym expansion.
//  Uses structured output for reliable processing of large skill sets.
//

import Foundation
import Observation
import SwiftyJSON

// MARK: - Processing Status

enum SkillsProcessingStatus: Equatable {
    case idle
    case processing(String)
    case completed(String)
    case failed(String)
}

// MARK: - Processing Result

struct SkillsProcessingResult {
    let operation: String
    let skillsProcessed: Int
    let skillsModified: Int
    let details: String
}

// MARK: - Deduplication Types

/// Represents a group of duplicate skills identified by LLM
struct DuplicateGroup: Codable {
    let canonicalName: String
    let skillIds: [String]
    let reasoning: String

    enum CodingKeys: String, CodingKey {
        case canonicalName = "canonical_name"
        case skillIds = "skill_ids"
        case reasoning
    }
}

/// Response from deduplication analysis
struct DeduplicationResponse: Codable {
    let duplicateGroups: [DuplicateGroup]

    enum CodingKeys: String, CodingKey {
        case duplicateGroups = "duplicate_groups"
    }
}

// MARK: - ATS Expansion Types

/// ATS variants for a single skill
struct SkillATSVariants: Codable {
    let skillId: String
    let variants: [String]

    enum CodingKeys: String, CodingKey {
        case skillId = "skill_id"
        case variants
    }
}

/// Response from ATS expansion
struct ATSExpansionResponse: Codable {
    let skills: [SkillATSVariants]
}

// MARK: - Skills Processing Service

@Observable
@MainActor
final class SkillsProcessingService {
    private weak var facade: LLMFacade?
    private let skillStore: SkillStore

    // State
    private(set) var status: SkillsProcessingStatus = .idle
    private(set) var progress: Double = 0.0
    private(set) var currentBatch: Int = 0
    private(set) var totalBatches: Int = 0

    // Configuration
    private var modelId: String {
        UserDefaults.standard.string(forKey: "skillsProcessingModelId") ?? DefaultModels.gemini
    }
    private let batchSize = 50  // Skills per LLM call

    init(skillStore: SkillStore, facade: LLMFacade?) {
        self.skillStore = skillStore
        self.facade = facade
        Logger.info("🔧 SkillsProcessingService initialized", category: .ai)
    }

    func updateFacade(_ facade: LLMFacade?) {
        self.facade = facade
    }

    // MARK: - Deduplication

    /// LLM-powered intelligent deduplication of skills.
    /// Identifies semantically equivalent skills even with different names/casing.
    /// Processes all skills in a single pass to catch duplicates across the entire set.
    func consolidateDuplicates() async throws -> SkillsProcessingResult {
        guard let facade = facade else {
            throw SkillsProcessingError.llmNotConfigured
        }

        let allSkills = skillStore.skills
        guard !allSkills.isEmpty else {
            return SkillsProcessingResult(
                operation: "Deduplication",
                skillsProcessed: 0,
                skillsModified: 0,
                details: "No skills to process"
            )
        }

        status = .processing("Analyzing \(allSkills.count) skills for duplicates...")
        Logger.info("🔧 Starting deduplication of \(allSkills.count) skills", category: .ai)

        // Build compact skill list for LLM analysis (all skills in one pass)
        // Format: "uuid: name [category]" - compact enough to fit hundreds of skills
        let skillDescriptions = allSkills.map { skill in
            "\(skill.id.uuidString): \(skill.canonical) [\(skill.category.rawValue)]"
        }

        // For very large skill sets (500+), we may need multiple passes
        // But typically ~420 skills at ~60 chars each = ~25KB, fits in one prompt
        let duplicateGroups: [DuplicateGroup]

        if allSkills.count > 500 {
            // Multi-pass for very large sets: first pass finds candidates, second confirms
            duplicateGroups = try await analyzeAllSkillsMultiPass(
                skills: skillDescriptions,
                facade: facade
            )
        } else {
            // Single pass for normal sets
            duplicateGroups = try await analyzeAllSkillsForDuplicates(
                skills: skillDescriptions,
                facade: facade
            )
        }

        // Apply deduplication
        status = .processing("Merging \(duplicateGroups.count) duplicate groups...")
        let mergeCount = applyDuplicateMerges(groups: duplicateGroups)

        let result = SkillsProcessingResult(
            operation: "Deduplication",
            skillsProcessed: allSkills.count,
            skillsModified: mergeCount,
            details: "Found \(duplicateGroups.count) duplicate groups, merged \(mergeCount) skills"
        )

        status = .completed("Merged \(mergeCount) duplicate skills")
        Logger.info("🔧 Deduplication complete: \(result.details)", category: .ai)

        return result
    }

    /// Analyze all skills in a single LLM call (for sets up to ~500 skills)
    private func analyzeAllSkillsForDuplicates(
        skills: [String],
        facade: LLMFacade
    ) async throws -> [DuplicateGroup] {
        let prompt = """
        Analyze the following \(skills.count) skills and identify groups of duplicates that should be merged.

        Skills (format: "uuid: name [category]"):
        \(skills.joined(separator: "\n"))

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
        - If no duplicates are found, return an empty duplicate_groups array
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "duplicate_groups": [
                    "type": "array",
                    "description": "Groups of duplicate skills to merge",
                    "items": [
                        "type": "object",
                        "properties": [
                            "canonical_name": [
                                "type": "string",
                                "description": "The best canonical name to use for this skill"
                            ],
                            "skill_ids": [
                                "type": "array",
                                "description": "UUIDs of all skills in this duplicate group",
                                "items": ["type": "string"]
                            ],
                            "reasoning": [
                                "type": "string",
                                "description": "Brief explanation of why these are duplicates"
                            ]
                        ],
                        "required": ["canonical_name", "skill_ids", "reasoning"]
                    ]
                ]
            ],
            "required": ["duplicate_groups"]
        ]

        let response: DeduplicationResponse = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: DeduplicationResponse.self,
            schema: schema,
            schemaName: "deduplication_analysis",
            maxOutputTokens: 32768,
            backend: .gemini
        )

        return response.duplicateGroups
    }

    /// Multi-pass analysis for very large skill sets (500+)
    /// First pass: get candidate duplicate groups by category
    /// Second pass: confirm and refine
    private func analyzeAllSkillsMultiPass(
        skills: [String],
        facade: LLMFacade
    ) async throws -> [DuplicateGroup] {
        totalBatches = 2
        var allGroups: [DuplicateGroup] = []

        // Pass 1: Quick scan by sending skill names only (not UUIDs)
        currentBatch = 1
        progress = 0.5
        status = .processing("Pass 1: Identifying candidate duplicates...")

        // Group skills by category for more focused analysis
        var skillsByCategory: [String: [String]] = [:]
        for skill in skills {
            if let catStart = skill.lastIndex(of: "["),
               let catEnd = skill.lastIndex(of: "]") {
                let category = String(skill[skill.index(after: catStart)..<catEnd])
                skillsByCategory[category, default: []].append(skill)
            }
        }

        // Analyze each category separately
        for (_, categorySkills) in skillsByCategory {
            if categorySkills.count < 2 { continue }

            let groups = try await analyzeAllSkillsForDuplicates(
                skills: categorySkills,
                facade: facade
            )
            allGroups.append(contentsOf: groups)
        }

        // Pass 2: Cross-category check (skills that might be duplicated across categories)
        currentBatch = 2
        progress = 1.0
        status = .processing("Pass 2: Cross-category verification...")

        // This is a simplified cross-check - for now just return what we found
        // A full implementation would look for same-name skills across categories

        return allGroups
    }

    private func applyDuplicateMerges(groups: [DuplicateGroup]) -> Int {
        var mergedCount = 0

        for group in groups {
            guard group.skillIds.count > 1 else { continue }

            // Find all skills in this group
            let skillUUIDs = group.skillIds.compactMap { UUID(uuidString: $0) }
            let skills = skillStore.skills.filter { skillUUIDs.contains($0.id) }

            guard skills.count > 1 else { continue }

            // Pick the primary skill (first one, or one with most evidence)
            let primary = skills.max { $0.evidence.count < $1.evidence.count } ?? skills[0]

            // Update canonical name if LLM suggested a better one
            primary.canonical = group.canonicalName

            // Merge evidence, ATS variants, and related skills from all duplicates
            var mergedEvidence = primary.evidence
            var mergedVariants = Set(primary.atsVariants)
            var mergedRelated = Set(primary.relatedSkills)

            // Take highest proficiency
            var highestProficiency = primary.proficiency

            for skill in skills where skill.id != primary.id {
                // Merge evidence (dedupe by document+location)
                for evidence in skill.evidence {
                    let exists = mergedEvidence.contains {
                        $0.documentId == evidence.documentId && $0.location == evidence.location
                    }
                    if !exists {
                        mergedEvidence.append(evidence)
                    }
                }

                // Merge ATS variants (include old canonical names)
                mergedVariants.insert(skill.canonical)
                mergedVariants.formUnion(skill.atsVariants)

                // Merge related skills
                mergedRelated.formUnion(skill.relatedSkills)

                // Take highest proficiency
                if skill.proficiency.sortOrder < highestProficiency.sortOrder {
                    highestProficiency = skill.proficiency
                }

                // Delete the duplicate
                skillStore.delete(skill)
                mergedCount += 1
            }

            // Remove canonical name from variants
            mergedVariants.remove(primary.canonical)

            // Update primary with merged data
            primary.evidence = mergedEvidence
            primary.atsVariants = Array(mergedVariants)
            primary.relatedSkills = Array(mergedRelated)
            primary.proficiency = highestProficiency
            skillStore.update(primary)
        }

        return mergedCount
    }

    // MARK: - ATS Expansion

    /// LLM-powered ATS synonym expansion for all skills.
    /// Adds common ATS variants for better resume matching.
    func expandATSSynonyms() async throws -> SkillsProcessingResult {
        guard let facade = facade else {
            throw SkillsProcessingError.llmNotConfigured
        }

        let allSkills = skillStore.skills
        guard !allSkills.isEmpty else {
            return SkillsProcessingResult(
                operation: "ATS Expansion",
                skillsProcessed: 0,
                skillsModified: 0,
                details: "No skills to process"
            )
        }

        status = .processing("Generating ATS synonyms...")
        Logger.info("🔧 Starting ATS expansion for \(allSkills.count) skills", category: .ai)

        // Process in batches
        let batches = stride(from: 0, to: allSkills.count, by: batchSize).map {
            Array(allSkills[$0..<min($0 + batchSize, allSkills.count)])
        }

        totalBatches = batches.count
        var totalModified = 0

        for (index, batch) in batches.enumerated() {
            currentBatch = index + 1
            progress = Double(currentBatch) / Double(totalBatches)
            status = .processing("Processing batch \(currentBatch)/\(totalBatches)...")

            let expansions = try await generateATSVariants(
                skills: batch,
                facade: facade
            )

            // Apply expansions to skills
            for expansion in expansions {
                guard let uuid = UUID(uuidString: expansion.skillId),
                      let skill = skillStore.skill(withId: uuid) else { continue }

                // Add new variants (don't replace existing ones)
                let existingVariants = Set(skill.atsVariants.map { $0.lowercased() })
                let newVariants = expansion.variants.filter { !existingVariants.contains($0.lowercased()) }

                if !newVariants.isEmpty {
                    skill.atsVariants = skill.atsVariants + newVariants
                    skillStore.update(skill)
                    totalModified += 1
                }
            }
        }

        let result = SkillsProcessingResult(
            operation: "ATS Expansion",
            skillsProcessed: allSkills.count,
            skillsModified: totalModified,
            details: "Added ATS variants to \(totalModified) skills"
        )

        status = .completed("Added variants to \(totalModified) skills")
        Logger.info("🔧 ATS expansion complete: \(result.details)", category: .ai)

        return result
    }

    private func generateATSVariants(
        skills: [Skill],
        facade: LLMFacade
    ) async throws -> [SkillATSVariants] {
        let skillDescriptions = skills.map { skill in
            let existing = skill.atsVariants.isEmpty ? "" : " (existing: \(skill.atsVariants.joined(separator: ", ")))"
            return "\(skill.id.uuidString): \(skill.canonical)\(existing)"
        }

        let prompt = """
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

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "skills": [
                    "type": "array",
                    "description": "ATS variants for each skill",
                    "items": [
                        "type": "object",
                        "properties": [
                            "skill_id": [
                                "type": "string",
                                "description": "UUID of the skill"
                            ],
                            "variants": [
                                "type": "array",
                                "description": "ATS synonym variants",
                                "items": ["type": "string"]
                            ]
                        ],
                        "required": ["skill_id", "variants"]
                    ]
                ]
            ],
            "required": ["skills"]
        ]

        let response: ATSExpansionResponse = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: ATSExpansionResponse.self,
            schema: schema,
            schemaName: "ats_expansion",
            maxOutputTokens: 32768,
            backend: .gemini
        )

        return response.skills
    }

    // MARK: - Combined Processing

    /// Run both deduplication and ATS expansion in sequence
    func processAllSkills() async throws -> [SkillsProcessingResult] {
        var results: [SkillsProcessingResult] = []

        // First deduplicate
        let dedupeResult = try await consolidateDuplicates()
        results.append(dedupeResult)

        // Then expand ATS variants
        let atsResult = try await expandATSSynonyms()
        results.append(atsResult)

        return results
    }

    func reset() {
        status = .idle
        progress = 0.0
        currentBatch = 0
        totalBatches = 0
    }
}

// MARK: - Errors

enum SkillsProcessingError: LocalizedError {
    case llmNotConfigured
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .llmNotConfigured:
            return "LLM service is not configured"
        case .invalidResponse:
            return "Invalid response from LLM"
        }
    }
}
