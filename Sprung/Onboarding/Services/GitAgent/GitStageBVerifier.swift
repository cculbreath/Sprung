//
//  GitStageBVerifier.swift
//  Sprung
//
//  Stage B of the git analysis pipeline (WS3.3): evidence deep-dive.
//
//  Stage A (GitAnalysisAgent's tool loop) produces a CANDIDATE skill inventory.
//  Stage B groups the candidates by category and runs one bounded structured
//  verification call per group: the prompt carries the group's candidate skills,
//  their evidence pointers, and the deterministic git-evidence block. The model
//  must return a per-skill verdict — confirm (with ≥2 concrete citations) or drop.
//
//  Prompt caching: the Stage B instructions and the rendered git evidence are
//  byte-identical system blocks across all group calls, with a cache breakpoint
//  on the last system block. The first group call is awaited alone to warm the
//  cache; the remaining groups then fan out (max 3 concurrent) and read it.
//
//  Failure policy: Stage B degrades gracefully per group — if a group's
//  verification call fails, that group's candidates are kept unchanged.
//

import Foundation
import SwiftOpenAI

// MARK: - Verdict Types

/// One Stage B judgment for a candidate skill.
/// JSON keys are camelCase matching property names (project standard).
struct StageBVerdict: Codable, Sendable {
    /// Exact canonical name of the candidate skill being judged
    let canonical: String
    /// "confirm" | "drop"
    let verdict: String
    /// Concrete evidence citations (file paths / commit refs / git-evidence rows)
    let citations: [String]
    /// Evidence-based justification referencing the citations
    let justification: String
}

/// Structured response for one verification group.
struct StageBGroupResponse: Codable, Sendable {
    let verdicts: [StageBVerdict]
}

// MARK: - Stage B Verifier

@MainActor
final class GitStageBVerifier {
    /// Cap on the number of category groups that get a verification call.
    /// Groups beyond the cap (smallest first) pass through unverified.
    static let maxGroups = 8
    /// Bounded fan-out after the cache-warming first call.
    static let maxConcurrentGroupCalls = 3
    /// A confirm verdict with fewer concrete citations than this is dropped.
    static let minimumConfirmCitations = 2

    private let facade: LLMFacade
    private let modelId: String
    /// System blocks shared verbatim by every group call (cache breakpoint on
    /// the last block caches instructions + git evidence across the fan-out).
    private let systemBlocks: [AnthropicSystemBlock]

    init(facade: LLMFacade, modelId: String, gitEvidence: String) {
        self.facade = facade
        self.modelId = modelId
        if gitEvidence.isEmpty {
            self.systemBlocks = [
                AnthropicSystemBlock(text: Self.systemPrompt, cacheControl: .ephemeral)
            ]
        } else {
            self.systemBlocks = [
                AnthropicSystemBlock(text: Self.systemPrompt),
                AnthropicSystemBlock(
                    text: "<git_evidence>\n\(gitEvidence)\n</git_evidence>",
                    cacheControl: .ephemeral
                )
            ]
        }
    }

    // MARK: - Public API

    /// Verify candidate skills and return the surviving (possibly re-graded) set.
    /// Never throws — per-group failures keep that group's candidates.
    func verify(
        candidates: [Skill],
        onProgress: (@MainActor (String) async -> Void)? = nil
    ) async -> [Skill] {
        guard !candidates.isEmpty else { return candidates }

        // Group by category, largest groups first (deterministic tie-break by name)
        var skillsByCategory: [String: [Skill]] = [:]
        for skill in candidates {
            skillsByCategory[skill.category, default: []].append(skill)
        }
        let orderedCategories = skillsByCategory.keys.sorted { lhs, rhs in
            let lhsCount = skillsByCategory[lhs]?.count ?? 0
            let rhsCount = skillsByCategory[rhs]?.count ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return lhs < rhs
        }

        let verifiedCategories = Array(orderedCategories.prefix(Self.maxGroups))
        let passthroughCategories = Array(orderedCategories.dropFirst(Self.maxGroups))
        if !passthroughCategories.isEmpty {
            let passthroughCount = passthroughCategories.reduce(0) { $0 + (skillsByCategory[$1]?.count ?? 0) }
            Logger.warning(
                "⚠️ GitStageB: \(orderedCategories.count) groups exceed cap of \(Self.maxGroups) — " +
                "\(passthroughCount) candidate(s) in \(passthroughCategories.count) smallest group(s) pass through unverified",
                category: .ai
            )
        }

        // Build payloads up front (Strings only cross into child tasks)
        let groups: [(name: String, payload: String)] = verifiedCategories.map { category in
            (name: category, payload: buildGroupPayload(category: category, skills: skillsByCategory[category] ?? []))
        }

        Logger.info(
            "🔎 GitStageB: verifying \(candidates.count) candidates across \(groups.count) group(s) (model: \(modelId))",
            category: .ai
        )

        // Warm the shared prefix with one awaited call, then fan out the rest
        // (concurrent identical-prefix requests each pay full cost until the
        // first response starts streaming).
        var responses: [Int: StageBGroupResponse] = [:]
        if let first = groups.first {
            await onProgress?("Stage B: verifying '\(first.name)' (1/\(groups.count))...")
            if let response = await fetchVerdicts(groupName: first.name, payload: first.payload) {
                responses[0] = response
            }
        }

        if groups.count > 1 {
            await onProgress?("Stage B: verifying remaining \(groups.count - 1) group(s)...")
            let fanOutGroups = groups.enumerated().dropFirst().map { (index: $0.offset, name: $0.element.name, payload: $0.element.payload) }
            let results = await withTaskGroup(
                of: (Int, StageBGroupResponse?).self,
                returning: [(Int, StageBGroupResponse?)].self
            ) { taskGroup in
                var nextSlot = 0
                while nextSlot < Self.maxConcurrentGroupCalls && nextSlot < fanOutGroups.count {
                    let work = fanOutGroups[nextSlot]
                    taskGroup.addTask { [self] in
                        (work.index, await self.fetchVerdicts(groupName: work.name, payload: work.payload))
                    }
                    nextSlot += 1
                }
                var collected: [(Int, StageBGroupResponse?)] = []
                for await result in taskGroup {
                    collected.append(result)
                    if nextSlot < fanOutGroups.count {
                        let work = fanOutGroups[nextSlot]
                        taskGroup.addTask { [self] in
                            (work.index, await self.fetchVerdicts(groupName: work.name, payload: work.payload))
                        }
                        nextSlot += 1
                    }
                }
                return collected
            }
            for (index, response) in results {
                if let response {
                    responses[index] = response
                }
            }
        }

        // Apply verdicts group by group
        var totalConfirmed = 0
        var totalDropped = 0
        var survivors: [Skill] = []
        for (index, group) in groups.enumerated() {
            let groupSkills = skillsByCategory[group.name] ?? []
            let outcome = apply(responses[index], to: groupSkills, groupName: group.name)
            survivors.append(contentsOf: outcome.kept)
            totalConfirmed += outcome.confirmed
            totalDropped += outcome.dropped
        }
        for category in passthroughCategories {
            survivors.append(contentsOf: skillsByCategory[category] ?? [])
        }

        Logger.info(
            "✅ GitStageB: \(candidates.count) candidates in → \(totalConfirmed) confirmed, " +
            "\(totalDropped) dropped, \(survivors.count) kept",
            category: .ai
        )
        await onProgress?("Stage B complete: \(totalConfirmed) confirmed, \(totalDropped) dropped")

        return survivors
    }

    // MARK: - Verification Call

    private func fetchVerdicts(groupName: String, payload: String) async -> StageBGroupResponse? {
        do {
            return try await facade.executeStructuredWithAnthropicBlocks(
                systemContent: systemBlocks,
                userBlocks: [.text(AnthropicTextBlock(text: payload))],
                modelId: modelId,
                responseType: StageBGroupResponse.self,
                schema: Self.verdictSchema,
                maxTokens: 8192
            )
        } catch {
            Logger.warning(
                "⚠️ GitStageB: verification failed for group '\(groupName)' — keeping its candidates: \(error.localizedDescription)",
                category: .ai
            )
            return nil
        }
    }

    // MARK: - Verdict Application

    private func apply(
        _ response: StageBGroupResponse?,
        to skills: [Skill],
        groupName: String
    ) -> (kept: [Skill], confirmed: Int, dropped: Int) {
        guard let response else {
            Logger.warning(
                "⚠️ GitStageB group '\(groupName)': no verdicts — keeping all \(skills.count) candidate(s)",
                category: .ai
            )
            return (skills, 0, 0)
        }

        var verdictsByName: [String: StageBVerdict] = [:]
        for verdict in response.verdicts {
            verdictsByName[Self.normalized(verdict.canonical)] = verdict
        }

        var kept: [Skill] = []
        var confirmed = 0
        var dropped = 0
        var unjudged = 0

        for skill in skills {
            guard let verdict = verdictsByName[Self.normalized(skill.canonical)] else {
                unjudged += 1
                kept.append(skill)
                continue
            }

            switch verdict.verdict {
            case "confirm":
                if verdict.citations.count >= Self.minimumConfirmCitations {
                    confirmed += 1
                    kept.append(skill)
                } else {
                    // A confirm without concrete citations lets Stage A overclaims
                    // through the audit — it does not meet the confirm bar, so the
                    // candidate is dropped mechanically.
                    Logger.warning(
                        "⚠️ GitStageB: '\(skill.canonical)' confirmed with \(verdict.citations.count) citation(s) " +
                        "(< \(Self.minimumConfirmCitations)) — dropping",
                        category: .ai
                    )
                    dropped += 1
                }
            case "drop":
                Logger.info("🗑️ GitStageB: dropped '\(skill.canonical)' — \(verdict.justification)", category: .ai)
                dropped += 1
            default:
                Logger.warning("⚠️ GitStageB: unknown verdict '\(verdict.verdict)' for '\(skill.canonical)' — keeping", category: .ai)
                unjudged += 1
                kept.append(skill)
            }
        }

        let unjudgedSuffix = unjudged > 0 ? ", \(unjudged) unjudged (kept)" : ""
        Logger.info(
            "🔎 GitStageB group '\(groupName)': \(skills.count) in → \(confirmed) confirmed, " +
            "\(dropped) dropped\(unjudgedSuffix)",
            category: .ai
        )

        return (kept, confirmed, dropped)
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Payload

    private func buildGroupPayload(category: String, skills: [Skill]) -> String {
        var lines: [String] = [
            "Verify the following \(skills.count) candidate skill(s) in the category \"\(category)\".",
            "Return exactly one verdict per candidate, keyed by the candidate's exact canonical name.",
            ""
        ]
        for skill in skills {
            lines.append("### \(skill.canonical)")
            let evidence = skill.evidence
            if evidence.isEmpty {
                lines.append("- evidencePointers: (none provided)")
            } else {
                lines.append("- evidencePointers:")
                for item in evidence {
                    let context = item.context.isEmpty ? "" : " — \(item.context)"
                    lines.append("  - [\(item.strength.rawValue)] \(item.location)\(context)")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Prompt & Schema

    private static let systemPrompt = """
    You are Stage B of a two-stage git repository skill analysis: the evidence verifier.

    Stage A explored the repository with filesystem tools and produced a CANDIDATE skill \
    inventory. Each candidate arrives with evidence pointers (file paths, line ranges). \
    Your job is to audit one group of candidates against those pointers and the \
    deterministic <git_evidence> block (commit-history aggregates: per-directory tenure, \
    churn, monthly activity).

    For EACH candidate, return exactly one verdict:
    - "confirm": the evidence genuinely supports the skill. Requires AT LEAST 2 concrete \
    citations drawn from the candidate's evidence pointers and/or specific <git_evidence> \
    entries (file paths with line ranges, commit references, or named git-evidence rows), \
    plus a justification grounded in those citations.
    - "drop": the evidence does not survive scrutiny — a name-drop, generated or vendored \
    code, dependency-only usage, or pointers that do not substantiate the claim.

    Rules:
    - Every confirm must be grounded in its citations; a confirm without at least 2 \
    concrete citations will be dropped mechanically.
    - A single impressive file is NOT sufficient on its own. Strong confirmations pair \
    code evidence with longitudinal support from <git_evidence> (tenure and sustained \
    activity where the skill lives).
    - Be conservative: when pointers are vague, unrelated, or the evidence is too thin \
    to defend, drop rather than confirm.
    - Use each candidate's exact canonical name in your verdict.
    """

    /// Structured-output schema for one group's verdicts.
    /// JSON keys are camelCase matching the Swift property names.
    static let verdictSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "verdicts": [
                "type": "array",
                "description": "Exactly one verdict per candidate skill in the group",
                "items": [
                    "type": "object",
                    "properties": [
                        "canonical": [
                            "type": "string",
                            "description": "Exact canonical name of the candidate skill being judged"
                        ],
                        "verdict": [
                            "type": "string",
                            "enum": ["confirm", "drop"]
                        ],
                        "citations": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Concrete evidence citations: file paths with line ranges, commit refs, or specific git-evidence rows. At least 2 for confirm."
                        ],
                        "justification": [
                            "type": "string",
                            "description": "Evidence-based justification referencing the citations"
                        ]
                    ],
                    "required": ["canonical", "verdict", "citations", "justification"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["verdicts"],
        "additionalProperties": false
    ]
}
