//
//  SkillBankCurationService.swift
//  Sprung
//
//  LLM-driven skill bank curation: dedup detection, over-granularity flagging,
//  and category normalization. Produces a reviewable plan — no auto-mutations.
//

import Foundation

// MARK: - Curation Plan Types

/// A complete curation plan containing all proposed changes.
struct SkillCurationPlan {
    var mergeProposals: [MergeProposal]
    var overGranularFlags: [OverGranularFlag]
    var categoryReassignments: [CategoryReassignment]
    var categoryConsolidations: [CategoryConsolidation]

    var isEmpty: Bool {
        mergeProposals.isEmpty && overGranularFlags.isEmpty &&
        categoryReassignments.isEmpty && categoryConsolidations.isEmpty
    }

    var totalProposals: Int {
        mergeProposals.count + overGranularFlags.count +
        categoryReassignments.count + categoryConsolidations.count
    }
}

/// Proposal to merge a cluster of duplicate skills.
struct MergeProposal: Identifiable {
    let id = UUID()
    var canonicalName: String
    let mergedSkillIds: [UUID]
    let mergedSkillNames: [String]
    let rationale: String
    var accepted: Bool = true
}

/// Flag indicating a skill is too granular for resume use.
struct OverGranularFlag: Identifiable {
    let id = UUID()
    let skillId: UUID
    let skillName: String
    let currentCategory: String
    let rationale: String
    var accepted: Bool = true
}

/// Proposal to move a skill to a different category.
struct CategoryReassignment: Identifiable {
    let id = UUID()
    let skillId: UUID
    let skillName: String
    let currentCategory: String
    let proposedCategory: String
    let rationale: String
    var accepted: Bool = true
}

/// Proposal to consolidate near-duplicate or small categories.
struct CategoryConsolidation: Identifiable {
    let id = UUID()
    let fromCategory: String
    let toCategory: String
    let affectedSkillCount: Int
    let rationale: String
    var accepted: Bool = true
}

// MARK: - LLM Response Types

private struct CurationResponse: Codable {
    let mergeProposals: [MergeProposalDTO]
    let overGranularFlags: [OverGranularFlagDTO]
    let categoryReassignments: [CategoryReassignmentDTO]
    let categoryConsolidations: [CategoryConsolidationDTO]
}

private struct MergeProposalDTO: Codable {
    let canonicalName: String
    let skillIds: [String]
    let rationale: String
}

private struct OverGranularFlagDTO: Codable {
    let skillId: String
    let rationale: String
}

private struct CategoryReassignmentDTO: Codable {
    let skillId: String
    let proposedCategory: String
    let rationale: String
}

private struct CategoryConsolidationDTO: Codable {
    let fromCategory: String
    let toCategory: String
    let rationale: String
}

// MARK: - Service

/// LLM-driven skill bank curation service.
/// Produces a reviewable plan; does not auto-mutate.
@MainActor
final class SkillBankCurationService {
    private let skillStore: SkillStore
    private let llmFacade: LLMFacade

    private func getModelId() throws -> String {
        guard let modelId = UserDefaults.standard.string(forKey: "skillCurationModelId"), !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "skillCurationModelId",
                operationName: "Skill Bank Curation"
            )
        }
        return modelId
    }

    init(skillStore: SkillStore, llmFacade: LLMFacade) {
        self.skillStore = skillStore
        self.llmFacade = llmFacade
    }

    /// Generate a curation plan from the current skill bank.
    /// This is the main entry point. Returns a plan for user review.
    func generateCurationPlan() async throws -> SkillCurationPlan {
        let allSkills = skillStore.skills
        guard !allSkills.isEmpty else {
            return SkillCurationPlan(
                mergeProposals: [],
                overGranularFlags: [],
                categoryReassignments: [],
                categoryConsolidations: []
            )
        }

        Logger.info("Starting skill bank curation for \(allSkills.count) skills", category: .ai)

        let modelId = try getModelId()
        let prompt = buildCurationPrompt(skills: allSkills)

        let response: CurationResponse = try await llmFacade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: CurationResponse.self,
            schema: curationSchema,
            schemaName: "skill_curation",
            backend: .openRouter
        )

        let plan = convertResponseToPlan(response: response, skills: allSkills)
        Logger.info("Curation plan: \(plan.mergeProposals.count) merges, \(plan.overGranularFlags.count) over-granular, \(plan.categoryReassignments.count) reassignments, \(plan.categoryConsolidations.count) consolidations", category: .ai)
        return plan
    }

    /// Apply accepted changes from a curation plan.
    func applyCurationPlan(_ plan: SkillCurationPlan) {
        var totalChanges = 0

        // Apply accepted merge proposals
        for proposal in plan.mergeProposals where proposal.accepted {
            totalChanges += applyMerge(proposal)
        }

        // Apply accepted over-granular removals
        for flag in plan.overGranularFlags where flag.accepted {
            if let skill = skillStore.skill(withId: flag.skillId) {
                skillStore.delete(skill)
                totalChanges += 1
            }
        }

        // Apply accepted category reassignments
        for reassignment in plan.categoryReassignments where reassignment.accepted {
            if let skill = skillStore.skill(withId: reassignment.skillId) {
                skill.category = reassignment.proposedCategory
                skillStore.update(skill)
                totalChanges += 1
            }
        }

        // Apply accepted category consolidations
        for consolidation in plan.categoryConsolidations where consolidation.accepted {
            let affectedSkills = skillStore.skills.filter { $0.category == consolidation.fromCategory }
            for skill in affectedSkills {
                skill.category = consolidation.toCategory
                skillStore.update(skill)
            }
            if !affectedSkills.isEmpty {
                totalChanges += affectedSkills.count
            }
        }

        Logger.info("Applied \(totalChanges) curation changes", category: .ai)
    }

    // MARK: - Merge Application

    private func applyMerge(_ proposal: MergeProposal) -> Int {
        let skills = proposal.mergedSkillIds.compactMap { skillStore.skill(withId: $0) }
        guard skills.count > 1 else { return 0 }

        // Pick primary: most evidence, or first
        let primary = skills.max { $0.evidence.count < $1.evidence.count } ?? skills[0]
        primary.canonical = proposal.canonicalName

        // Union evidence, ATS variants, related skills
        var mergedEvidence = primary.evidence
        var mergedVariants = Set(primary.atsVariants)
        var mergedRelated = Set(primary.relatedSkills)
        var highestProficiency = primary.proficiency

        var mergedCount = 0
        for skill in skills where skill.id != primary.id {
            // Merge evidence (dedupe)
            for evidence in skill.evidence {
                let exists = mergedEvidence.contains {
                    $0.documentId == evidence.documentId && $0.location == evidence.location
                }
                if !exists {
                    mergedEvidence.append(evidence)
                }
            }

            // Merge ATS variants (include old canonical)
            mergedVariants.insert(skill.canonical)
            mergedVariants.formUnion(skill.atsVariants)

            // Merge related skills
            mergedRelated.formUnion(skill.relatedSkills)

            // Take highest proficiency
            if skill.proficiency.sortOrder < highestProficiency.sortOrder {
                highestProficiency = skill.proficiency
            }

            skillStore.delete(skill)
            mergedCount += 1
        }

        // Remove canonical name from variants
        mergedVariants.remove(primary.canonical)

        primary.evidence = mergedEvidence
        primary.atsVariants = Array(mergedVariants)
        primary.relatedSkills = Array(mergedRelated)
        primary.proficiency = highestProficiency
        skillStore.update(primary)

        return mergedCount
    }

    // MARK: - Prompt Building

    private func buildCurationPrompt(skills: [Skill]) -> String {
        let grouped = Dictionary(grouping: skills) { $0.category }
        let categoryStats = grouped.map { "\($0.key): \($0.value.count) skills" }.sorted().joined(separator: "\n")

        let skillDescriptions = skills.map { skill in
            let evidenceCount = skill.evidence.count
            return "\(skill.id.uuidString): \(skill.canonical) [\(skill.category)] (proficiency: \(skill.proficiency.rawValue), evidence: \(evidenceCount))"
        }.joined(separator: "\n")

        return """
        You are a resume skills expert curating a skill bank. Analyze the following \(skills.count) skills and produce a curation plan.

        ## Category Distribution
        \(categoryStats)

        ## Skills (format: "uuid: name [category] (proficiency, evidence count)")
        \(skillDescriptions)

        ## Your Tasks

        ### 1. Identify Duplicate Clusters
        Find skills that refer to the same underlying competency. Examples:
        - "Machining" and "Manual Machining" and "Machining & Fabrication" are the same skill
        - "Mentoring" and "Mentoring & Advising" are the same skill
        - "State Machines" and "State Machine Architecture" are the same skill
        - "C++" and "Embedded C++" may or may not be the same (use judgment)
        - "AWS" and "Azure" are NOT duplicates (different platforms)
        - "React" and "React Native" are NOT duplicates (different frameworks)

        For each cluster, select the best canonical name and list all skill IDs to merge.

        ### 2. Flag Over-Granular Skills
        Flag skills that are implementation details, not resume-level skills. A hiring manager would not look for these on a resume. Examples:
        - "Circular Buffers" (implementation detail of embedded systems)
        - "EEPROM Management" (implementation detail)
        - "RPM Measurement" (too specific)
        - "Rotary Encoders" (hardware component, not a skill)
        - "Hardware Interrupts" (implementation detail)

        Do NOT flag legitimate specialized skills. "Embedded Systems" is fine; "Interrupt Service Routines" is too granular.

        ### 3. Suggest Category Reassignments
        Identify skills that are in the wrong category. For example:
        - A writing skill in "Tools & Software" should move to "Communication & Writing"
        - A methodology in "Domain Expertise" should move to "Methodologies & Processes"

        ### 4. Suggest Category Consolidations
        - Merge near-identical category names (e.g., "Programming" vs "Programming Languages" -> pick one)
        - Flag categories with fewer than 3 skills for consolidation into a related category
        - Flag categories with more than 30% of all skills for potential splitting (but only if a natural split exists)

        ## Important
        - Be conservative: only flag clear duplicates, not similar-but-distinct skills
        - Preserve domain-specific skills that a specialist would value
        - The user reviews every suggestion before it's applied
        """
    }

    // MARK: - Schema

    private var curationSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "mergeProposals": [
                    "type": "array",
                    "description": "Clusters of duplicate skills to merge",
                    "items": [
                        "type": "object",
                        "properties": [
                            "canonicalName": [
                                "type": "string",
                                "description": "Best canonical name for the merged skill"
                            ],
                            "skillIds": [
                                "type": "array",
                                "description": "UUIDs of all skills in this duplicate cluster",
                                "items": ["type": "string"]
                            ],
                            "rationale": [
                                "type": "string",
                                "description": "Why these skills should be merged"
                            ]
                        ],
                        "required": ["canonicalName", "skillIds", "rationale"]
                    ]
                ],
                "overGranularFlags": [
                    "type": "array",
                    "description": "Skills that are too granular for resume use",
                    "items": [
                        "type": "object",
                        "properties": [
                            "skillId": [
                                "type": "string",
                                "description": "UUID of the over-granular skill"
                            ],
                            "rationale": [
                                "type": "string",
                                "description": "Why this skill is too granular"
                            ]
                        ],
                        "required": ["skillId", "rationale"]
                    ]
                ],
                "categoryReassignments": [
                    "type": "array",
                    "description": "Skills that should move to a different category",
                    "items": [
                        "type": "object",
                        "properties": [
                            "skillId": [
                                "type": "string",
                                "description": "UUID of the skill to reassign"
                            ],
                            "proposedCategory": [
                                "type": "string",
                                "description": "New category name"
                            ],
                            "rationale": [
                                "type": "string",
                                "description": "Why this skill belongs in the new category"
                            ]
                        ],
                        "required": ["skillId", "proposedCategory", "rationale"]
                    ]
                ],
                "categoryConsolidations": [
                    "type": "array",
                    "description": "Categories that should be merged into another",
                    "items": [
                        "type": "object",
                        "properties": [
                            "fromCategory": [
                                "type": "string",
                                "description": "Category to dissolve"
                            ],
                            "toCategory": [
                                "type": "string",
                                "description": "Category to absorb skills into"
                            ],
                            "rationale": [
                                "type": "string",
                                "description": "Why these categories should be merged"
                            ]
                        ],
                        "required": ["fromCategory", "toCategory", "rationale"]
                    ]
                ]
            ],
            "required": ["mergeProposals", "overGranularFlags", "categoryReassignments", "categoryConsolidations"]
        ]
    }

    // MARK: - Response Conversion

    private func convertResponseToPlan(response: CurationResponse, skills: [Skill]) -> SkillCurationPlan {
        let skillLookup = Dictionary(uniqueKeysWithValues: skills.map { ($0.id.uuidString, $0) })

        let mergeProposals: [MergeProposal] = response.mergeProposals.compactMap { dto in
            let uuids = dto.skillIds.compactMap { UUID(uuidString: $0) }
            let names = dto.skillIds.compactMap { skillLookup[$0]?.canonical }
            guard uuids.count > 1 else { return nil }
            return MergeProposal(
                canonicalName: dto.canonicalName,
                mergedSkillIds: uuids,
                mergedSkillNames: names,
                rationale: dto.rationale
            )
        }

        let overGranularFlags: [OverGranularFlag] = response.overGranularFlags.compactMap { dto in
            guard let uuid = UUID(uuidString: dto.skillId),
                  let skill = skillLookup[dto.skillId] else { return nil }
            return OverGranularFlag(
                skillId: uuid,
                skillName: skill.canonical,
                currentCategory: skill.category,
                rationale: dto.rationale
            )
        }

        let categoryReassignments: [CategoryReassignment] = response.categoryReassignments.compactMap { dto in
            guard let uuid = UUID(uuidString: dto.skillId),
                  let skill = skillLookup[dto.skillId] else { return nil }
            return CategoryReassignment(
                skillId: uuid,
                skillName: skill.canonical,
                currentCategory: skill.category,
                proposedCategory: dto.proposedCategory,
                rationale: dto.rationale
            )
        }

        let categoryConsolidations: [CategoryConsolidation] = response.categoryConsolidations.map { dto in
            let affected = skills.filter { $0.category == dto.fromCategory }.count
            return CategoryConsolidation(
                fromCategory: dto.fromCategory,
                toCategory: dto.toCategory,
                affectedSkillCount: affected,
                rationale: dto.rationale
            )
        }

        return SkillCurationPlan(
            mergeProposals: mergeProposals,
            overGranularFlags: overGranularFlags,
            categoryReassignments: categoryReassignments,
            categoryConsolidations: categoryConsolidations
        )
    }
}
