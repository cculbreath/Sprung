//
//  SkillsProcessingService.swift
//  Sprung
//
//  LLM-powered skills processing service for deduplication and ATS synonym expansion.
//  Uses parallel subagents for efficient ATS expansion across large skill sets.
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
}

/// Response from deduplication analysis
struct DeduplicationResponse: Codable {
    let duplicateGroups: [DuplicateGroup]
    /// Set to true if there are more duplicate groups that couldn't fit in this response
    let hasMore: Bool
    /// IDs of skills that have been processed (included in a duplicate group) in this response
    let processedSkillIds: [String]
}

// MARK: - ATS Expansion Types

/// ATS variants for a single skill
struct SkillATSVariants: Codable {
    let skillId: String
    let variants: [String]
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
    private let agentActivityTracker: AgentActivityTracker?

    // State
    private(set) var status: SkillsProcessingStatus = .idle
    private(set) var progress: Double = 0.0
    private(set) var currentBatch: Int = 0
    private(set) var totalBatches: Int = 0

    // Configuration - UserDefaults backed
    private var modelId: String {
        UserDefaults.standard.string(forKey: "skillsProcessingModelId") ?? "gemini-2.5-flash"
    }

    private var parallelAgentCount: Int {
        let count = UserDefaults.standard.integer(forKey: "skillsProcessingParallelAgents")
        return count > 0 ? count : 12  // Default to 12 if not set
    }

    init(skillStore: SkillStore, facade: LLMFacade?, agentActivityTracker: AgentActivityTracker? = nil) {
        self.skillStore = skillStore
        self.facade = facade
        self.agentActivityTracker = agentActivityTracker
        Logger.info("🔧 SkillsProcessingService initialized", category: .ai)
    }

    func updateFacade(_ facade: LLMFacade?) {
        self.facade = facade
    }

    // MARK: - Deduplication

    /// LLM-powered intelligent deduplication of skills.
    /// Identifies semantically equivalent skills even with different names/casing.
    /// Uses model max tokens to handle large skill sets in a single pass.
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
        let skillDescriptions = allSkills.map { skill in
            "\(skill.id.uuidString): \(skill.canonical) [\(skill.category.rawValue)]"
        }

        let duplicateGroups = try await analyzeAllSkillsForDuplicates(
            skills: skillDescriptions,
            facade: facade
        )

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

    /// Analyze all skills for duplicates, handling multi-part responses if output exceeds token limit.
    /// The LLM sees ALL skills in input but can output in multiple parts if needed.
    private func analyzeAllSkillsForDuplicates(
        skills: [String],
        facade: LLMFacade
    ) async throws -> [DuplicateGroup] {
        var allDuplicateGroups: [DuplicateGroup] = []
        var processedSkillIds: Set<String> = []
        var partNumber = 1
        var hasMore = true

        while hasMore {
            let isFirstPart = partNumber == 1
            let prompt = buildDeduplicationPrompt(
                skills: skills,
                processedSkillIds: processedSkillIds,
                isFirstPart: isFirstPart,
                partNumber: partNumber
            )

            Logger.info("🔧 Deduplication part \(partNumber): analyzing skills (already processed: \(processedSkillIds.count))", category: .ai)

            let response: DeduplicationResponse = try await facade.executeStructuredWithDictionarySchema(
                prompt: prompt,
                modelId: modelId,
                as: DeduplicationResponse.self,
                schema: deduplicationSchema,
                schemaName: "deduplication_analysis",
                maxOutputTokens: 32768,  // Reduced to encourage multi-part
                backend: .gemini
            )

            allDuplicateGroups.append(contentsOf: response.duplicateGroups)
            processedSkillIds.formUnion(response.processedSkillIds)
            hasMore = response.hasMore
            partNumber += 1

            Logger.info("🔧 Part \(partNumber - 1) complete: \(response.duplicateGroups.count) groups, hasMore: \(hasMore)", category: .ai)

            // Safety limit
            if partNumber > 20 {
                Logger.warning("⚠️ Deduplication exceeded 20 parts, stopping", category: .ai)
                break
            }
        }

        Logger.info("🔧 Deduplication analysis complete: \(allDuplicateGroups.count) total groups across \(partNumber - 1) parts", category: .ai)
        return allDuplicateGroups
    }

    /// Build the prompt for deduplication, adjusting for continuation if needed
    private func buildDeduplicationPrompt(
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
    private var deduplicationSchema: [String: Any] {
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

    // MARK: - ATS Expansion with Parallel Agents

    /// LLM-powered ATS synonym expansion using parallel subagents.
    /// Divides skills into batches and processes them concurrently.
    /// Parent agent and subagents are tracked in the AgentActivityTracker.
    func expandATSSynonyms(parentAgentId: String? = nil) async throws -> SkillsProcessingResult {
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

        let agentCount = min(parallelAgentCount, allSkills.count)
        status = .processing("Launching \(agentCount) parallel ATS expansion agents...")
        Logger.info("🔧 Starting parallel ATS expansion with \(agentCount) agents for \(allSkills.count) skills", category: .ai)

        // Divide skills into batches for parallel processing
        let batchSize = max(1, (allSkills.count + agentCount - 1) / agentCount)
        var batches: [[Skill]] = []
        for i in stride(from: 0, to: allSkills.count, by: batchSize) {
            let end = min(i + batchSize, allSkills.count)
            batches.append(Array(allSkills[i..<end]))
        }

        totalBatches = batches.count
        Logger.info("🔧 Created \(batches.count) batches of ~\(batchSize) skills each", category: .ai)

        // Update parent agent progress
        if let parentId = parentAgentId {
            agentActivityTracker?.appendTranscript(
                agentId: parentId,
                entryType: .system,
                content: "Launching \(batches.count) parallel ATS expansion agents",
                details: "\(allSkills.count) skills, ~\(batchSize) per agent"
            )
        }

        // Launch parallel tasks with child agent tracking
        let results = await withTaskGroup(of: (Int, String, [SkillATSVariants]).self) { group in
            for (index, batch) in batches.enumerated() {
                group.addTask { [self] in
                    // Create child agent ID
                    let childAgentId = UUID().uuidString

                    // Track child agent
                    if let tracker = await MainActor.run(body: { self.agentActivityTracker }),
                       let parentId = parentAgentId {
                        await MainActor.run {
                            tracker.trackChildAgent(
                                id: childAgentId,
                                parentAgentId: parentId,
                                type: .atsExpansion,
                                name: "ATS #\(index + 1)",
                                task: nil as Task<Void, Never>?
                            )
                            tracker.appendTranscript(
                                agentId: childAgentId,
                                entryType: .system,
                                content: "Processing \(batch.count) skills"
                            )
                        }
                    }

                    do {
                        let variants = try await self.generateATSVariantsForBatch(
                            skills: batch,
                            batchIndex: index,
                            facade: facade
                        )

                        // Mark child complete
                        if let tracker = await MainActor.run(body: { self.agentActivityTracker }) {
                            await MainActor.run {
                                tracker.appendTranscript(
                                    agentId: childAgentId,
                                    entryType: .system,
                                    content: "Generated \(variants.count) skill expansions"
                                )
                                tracker.markCompleted(agentId: childAgentId)
                            }
                        }

                        return (index, childAgentId, variants)
                    } catch {
                        Logger.warning("⚠️ ATS expansion batch \(index) failed: \(error.localizedDescription)", category: .ai)

                        // Mark child failed
                        if let tracker = await MainActor.run(body: { self.agentActivityTracker }) {
                            await MainActor.run {
                                tracker.markFailed(agentId: childAgentId, error: error.localizedDescription)
                            }
                        }

                        return (index, childAgentId, [])
                    }
                }
            }

            var allResults: [(Int, String, [SkillATSVariants])] = []
            for await result in group {
                allResults.append(result)
                await MainActor.run {
                    currentBatch = allResults.count
                    progress = Double(currentBatch) / Double(totalBatches)
                    status = .processing("Completed \(currentBatch)/\(totalBatches) agents...")
                }
            }
            return allResults
        }

        // Apply all expansions
        var totalModified = 0
        for (_, _, expansions) in results {
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
            details: "Added ATS variants to \(totalModified) skills using \(batches.count) parallel agents"
        )

        status = .completed("Added variants to \(totalModified) skills")
        Logger.info("🔧 ATS expansion complete: \(result.details)", category: .ai)

        return result
    }

    /// Generate ATS variants for a single batch (runs as subagent)
    private nonisolated func generateATSVariantsForBatch(
        skills: [Skill],
        batchIndex: Int,
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

        let modelId = await MainActor.run { self.modelId }

        Logger.debug("🔧 ATS batch \(batchIndex): Processing \(skills.count) skills", category: .ai)

        let response: ATSExpansionResponse = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: ATSExpansionResponse.self,
            schema: schema,
            schemaName: "ats_expansion",
            maxOutputTokens: 32768,
            backend: .gemini
        )

        Logger.debug("🔧 ATS batch \(batchIndex): Generated variants for \(response.skills.count) skills", category: .ai)

        return response.skills
    }

    // MARK: - Combined Processing

    /// Run both deduplication and ATS expansion in sequence.
    /// Tracks the main agent and spawns child agents for parallel ATS expansion.
    func processAllSkills() async throws -> [SkillsProcessingResult] {
        var results: [SkillsProcessingResult] = []

        // Register the main skills processing agent
        let mainAgentId = UUID().uuidString
        agentActivityTracker?.trackAgent(
            id: mainAgentId,
            type: .skillsProcessing,
            name: "Skills Processing",
            task: nil as Task<Void, Never>?
        )
        agentActivityTracker?.appendTranscript(
            agentId: mainAgentId,
            entryType: .system,
            content: "Starting skills processing pipeline"
        )

        do {
            // Check for cancellation before starting
            try Task.checkCancellation()
            try agentActivityTracker?.checkCancellation(agentId: mainAgentId)

            // First deduplicate
            agentActivityTracker?.appendTranscript(
                agentId: mainAgentId,
                entryType: .system,
                content: "Phase 1: Deduplicating skills"
            )
            let dedupeResult = try await consolidateDuplicates()
            results.append(dedupeResult)

            // Check for cancellation after deduplication
            try Task.checkCancellation()
            try agentActivityTracker?.checkCancellation(agentId: mainAgentId)

            agentActivityTracker?.appendTranscript(
                agentId: mainAgentId,
                entryType: .system,
                content: "Deduplication complete",
                details: dedupeResult.details
            )

            // Then expand ATS variants with parallel child agents
            agentActivityTracker?.appendTranscript(
                agentId: mainAgentId,
                entryType: .system,
                content: "Phase 2: ATS variant expansion"
            )
            let atsResult = try await expandATSSynonyms(parentAgentId: mainAgentId)
            results.append(atsResult)

            // Check for cancellation after ATS expansion
            try Task.checkCancellation()
            try agentActivityTracker?.checkCancellation(agentId: mainAgentId)

            agentActivityTracker?.appendTranscript(
                agentId: mainAgentId,
                entryType: .system,
                content: "ATS expansion complete",
                details: atsResult.details
            )

            agentActivityTracker?.markCompleted(agentId: mainAgentId)
        } catch is CancellationError {
            // Agent was cancelled - don't mark as failed, it's already marked as killed
            Logger.info("⏹️ Skills processing cancelled", category: .ai)
            throw CancellationError()
        } catch {
            agentActivityTracker?.markFailed(agentId: mainAgentId, error: error.localizedDescription)
            throw error
        }

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
