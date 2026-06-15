//
//  SkillBankService.swift
//  Sprung
//
//  Service for extracting comprehensive skill inventories from documents.
//  Uses Anthropic structured output (output_config schema) against a cached
//  source block — either the actual PDF (Files API document block) or text.
//

import Foundation
import SwiftOpenAI

/// Service for generating per-document skill inventories
actor SkillBankService {
    private var llmFacade: LLMFacade?

    private func getModelId() throws -> String {
        try AnthropicDocumentAnalysisService.configuredModelId(operationName: "Skill Bank Extraction")
    }

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("🔧 SkillBankService initialized", category: .ai)
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    /// Extract skills from raw document text.
    /// Text documents are capped at 200K characters upstream and go in one pass.
    func extractSkills(
        documentId: String,
        filename: String,
        content: String
    ) async throws -> [Skill] {
        try await extractSkills(
            documentId: documentId,
            filename: filename,
            source: .text(AnthropicDocumentAnalysisService.sourceTextBlock(filename: filename, text: content))
        )
    }

    /// Extract skills from an analysis source (uploaded PDF or text block).
    func extractSkills(
        documentId: String,
        filename: String,
        source: DocumentAnalysisSource
    ) async throws -> [Skill] {
        guard let facade = llmFacade else {
            throw SkillBankError.llmNotConfigured
        }

        let modelId = try getModelId()
        let instructions = SkillBankPrompts.extractionPrompt(
            documentId: documentId,
            filename: filename,
            isPagedSource: source.isPaged
        )

        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            Logger.info("🔧 Extracting skills from: \(filename) (attempt \(attempt)/\(maxAttempts))", category: .ai)

            do {
                let response: SkillExtractionResponse = try await facade.executeStructuredWithAnthropicBlocks(
                    systemContent: DocumentAnalysisPrompts.systemBlocks,
                    userBlocks: DocumentAnalysisPrompts.userBlocks(source: source, instructions: instructions),
                    modelId: modelId,
                    responseType: SkillExtractionResponse.self,
                    schema: SkillBankPrompts.jsonSchema,
                    maxTokens: 32768
                )
                Logger.info("🔧 Extracted \(response.skills.count) skills", category: .ai)
                return response.skills
            } catch let error as ModelConfigurationError {
                throw error
            } catch {
                Logger.warning("🔧 Error on attempt \(attempt): \(error.localizedDescription)", category: .ai)
                if attempt < maxAttempts { continue }
                // Rethrow the underlying error so callers can surface the real
                // failure (e.g. an API 400) instead of a generic message.
                throw error
            }
        }

        throw SkillBankError.invalidResponse
    }

    /// Deduplicate skills by canonical name
    private func deduplicateSkills(_ skills: [Skill]) -> [Skill] {
        var merged: [String: Skill] = [:]

        for skill in skills {
            let key = skill.canonical.lowercased()
            if let existing = merged[key] {
                // Merge evidence
                var allEvidence = existing.evidence + skill.evidence
                // Dedupe by document+location
                var seen = Set<String>()
                allEvidence = allEvidence.filter { evidence in
                    let key = "\(evidence.documentId):\(evidence.location)"
                    if seen.contains(key) { return false }
                    seen.insert(key)
                    return true
                }

                // Union ATS variants
                let variants = Array(Set(existing.atsVariants + skill.atsVariants))

                merged[key] = Skill(
                    id: existing.id,
                    canonical: existing.canonical,
                    atsVariants: variants,
                    category: existing.category,
                    evidence: allEvidence,
                    relatedSkills: Array(Set(existing.relatedSkills + skill.relatedSkills)),
                    lastUsed: existing.lastUsed ?? skill.lastUsed,
                    // A skill stays implied only if EVERY source marked it implied
                    implied: existing.implied && skill.implied
                )
            } else {
                merged[key] = skill
            }
        }

        return Array(merged.values).sorted { $0.canonical < $1.canonical }
    }

    /// Merge skills from multiple documents into unified bank
    func mergeSkillBank(documentSkills: [[Skill]], sourceDocumentIds: [String]) -> SkillBank {
        let allSkills = documentSkills.flatMap { $0 }
        let merged = deduplicateSkills(allSkills)

        return SkillBank(
            skills: merged,
            generatedAt: Date(),
            sourceDocumentIds: sourceDocumentIds
        )
    }

    // MARK: - Curation Gate

    /// Outcome of the post-merge skill curation gate.
    struct SkillCurationOutcome {
        let skills: [Skill]
        let inputCount: Int
        let collapsedCount: Int
        let droppedImpliedCount: Int
    }

    /// LLM decision payload for curation. Keys are camelCase matching property names.
    private struct CurationDecisions: Codable {
        struct Merge: Codable {
            let intoSkillId: String
            let absorbedSkillIds: [String]
            let canonical: String?
            let reasoning: String
        }
        struct Drop: Codable {
            let skillId: String
            let reason: String
        }
        let merges: [Merge]
        let drops: [Drop]
    }

    /// Curate an aggregated skill bank: collapse over-granular entries into
    /// their parent skill (absorbed names become ATS variants), and drop
    /// implied skills with no supporting evidence beyond the inference itself.
    /// Runs a single structured Anthropic call under the card-merge model and
    /// applies the returned decisions locally so evidence is never rewritten.
    func curateSkills(_ skills: [Skill]) async throws -> SkillCurationOutcome {
        guard let facade = llmFacade else {
            throw SkillBankError.llmNotConfigured
        }
        guard skills.count > 1 else {
            return SkillCurationOutcome(skills: skills, inputCount: skills.count, collapsedCount: 0, droppedImpliedCount: 0)
        }

        let modelId = try ModelConfigResolver.resolve(key: "onboardingCardMergeModelId", operation: "Skill Curation")

        let prompt = SkillBankPrompts.curationPrompt(skillsJSON: curationInputJSON(for: skills))

        let decisions: CurationDecisions = try await facade.executeStructuredWithAnthropicBlocks(
            systemContent: [AnthropicSystemBlock(text: SkillBankPrompts.curationSystemPrompt)],
            userBlocks: [.text(AnthropicTextBlock(text: prompt))],
            modelId: modelId,
            responseType: CurationDecisions.self,
            schema: SkillBankPrompts.curationSchema,
            maxTokens: 16384
        )

        return apply(decisions: decisions, to: skills)
    }

    /// Compact, LLM-readable JSON for the curation prompt.
    private func curationInputJSON(for skills: [Skill]) -> String {
        let entries: [[String: Any]] = skills.map { skill in
            var entry: [String: Any] = [
                "id": skill.id.uuidString,
                "canonical": skill.canonical,
                "atsVariants": skill.atsVariants,
                "category": skill.category,
                "implied": skill.implied,
                "evidence": skill.evidence.map { evidence in
                    [
                        "documentId": evidence.documentId,
                        "location": evidence.location,
                        "context": evidence.context,
                        "strength": evidence.strength.rawValue
                    ]
                }
            ]
            if let lastUsed = skill.lastUsed {
                entry["lastUsed"] = lastUsed
            }
            return entry
        }

        guard let data = try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    /// Apply merge/drop decisions deterministically. Surviving skills keep
    /// their exact evidence; absorbed entries contribute their names as ATS
    /// variants plus their evidence.
    private func apply(decisions: CurationDecisions, to skills: [Skill]) -> SkillCurationOutcome {
        var byId: [String: Skill] = [:]
        for skill in skills {
            byId[skill.id.uuidString] = skill
        }

        var absorbedIds = Set<String>()
        var droppedIds = Set<String>()

        // Drops first: an absorbed-and-dropped conflict resolves to drop
        for drop in decisions.drops {
            guard let skill = byId[drop.skillId] else { continue }
            // Only implied skills are eligible for the unsupported-inference drop
            guard skill.implied else {
                Logger.debug("🔧 Curation: ignoring drop of non-implied skill '\(skill.canonical)'", category: .ai)
                continue
            }
            droppedIds.insert(drop.skillId)
            Logger.debug("🔧 Curation dropped implied skill '\(skill.canonical)': \(drop.reason)", category: .ai)
        }

        // Resolve transitive merge chains before applying. The model may return
        // chained decisions in any order (e.g. merge B→A then merge C→B); a
        // merge whose target was itself absorbed must re-route into the
        // surviving ancestor, otherwise the absorbed-into-absorbed data is
        // silently lost when the final filter removes both entries.
        var redirects: [String: String] = [:]
        for merge in decisions.merges {
            for absorbedId in merge.absorbedSkillIds where absorbedId != merge.intoSkillId {
                // First decision wins, matching the absorb-once semantics below
                if redirects[absorbedId] == nil {
                    redirects[absorbedId] = merge.intoSkillId
                }
            }
        }

        func resolveSurvivor(_ id: String) -> String? {
            var current = id
            var visited: Set<String> = [id]
            while let next = redirects[current] {
                guard visited.insert(next).inserted else {
                    Logger.warning("🔧 Curation: cyclic merge chain at '\(id)' — skipping merge", category: .ai)
                    return nil
                }
                current = next
            }
            return current
        }

        for merge in decisions.merges {
            guard let survivorId = resolveSurvivor(merge.intoSkillId),
                  let target = byId[survivorId],
                  !droppedIds.contains(survivorId) else { continue }

            if survivorId != merge.intoSkillId {
                Logger.debug("🔧 Curation: redirected chained merge target '\(merge.intoSkillId)' → '\(survivorId)'", category: .ai)
            }

            var variants = Set(target.atsVariants)
            var evidence = target.evidence
            var implied = target.implied

            for absorbedId in merge.absorbedSkillIds {
                guard absorbedId != survivorId,
                      !droppedIds.contains(absorbedId),
                      !absorbedIds.contains(absorbedId),
                      let absorbed = byId[absorbedId] else { continue }

                absorbedIds.insert(absorbedId)
                variants.insert(absorbed.canonical)
                variants.formUnion(absorbed.atsVariants)
                evidence.append(contentsOf: absorbed.evidence)
                implied = implied && absorbed.implied
            }

            // Dedupe evidence by document+location, same as deduplicateSkills
            var seenEvidence = Set<String>()
            evidence = evidence.filter { item in
                seenEvidence.insert("\(item.documentId):\(item.location)").inserted
            }

            // A rename only applies when this merge's stated target IS the
            // survivor; a redirected merge's rename was meant for the absorbed
            // intermediate, not the ancestor it re-routed into.
            if survivorId == merge.intoSkillId,
               let canonical = merge.canonical, !canonical.isEmpty, canonical != target.canonical {
                variants.insert(target.canonical)
                target.canonical = canonical
            }
            variants.remove(target.canonical)

            target.atsVariants = variants.sorted()
            target.evidence = evidence
            target.implied = implied
        }

        let curated = skills.filter { skill in
            let id = skill.id.uuidString
            return !absorbedIds.contains(id) && !droppedIds.contains(id)
        }

        return SkillCurationOutcome(
            skills: curated,
            inputCount: skills.count,
            collapsedCount: absorbedIds.count,
            droppedImpliedCount: droppedIds.count
        )
    }

    enum SkillBankError: Error, LocalizedError {
        case llmNotConfigured
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM facade is not configured"
            case .invalidResponse:
                return "Invalid response from LLM"
            }
        }
    }
}

/// Response wrapper for skill extraction
private struct SkillExtractionResponse: Codable {
    let skills: [Skill]
}
