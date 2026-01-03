//
//  NarrativeDeduplicationService.swift
//  Sprung
//
//  Service for intelligent deduplication of narrative knowledge cards.
//  Uses world-class LLMs to make nuanced merge decisions while preserving detail.
//

import Foundation

/// Service for intelligent deduplication of narrative knowledge cards.
/// Uses world-class LLMs to make nuanced merge decisions while preserving detail.
actor NarrativeDeduplicationService {
    private var llmFacade: LLMFacade?

    private var modelId: String {
        UserDefaults.standard.string(forKey: "narrativeDedupeModelId")
            ?? "openai/gpt-4.1"  // Default to high-quality model for merge decisions
    }

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("🔀 NarrativeDeduplicationService initialized", category: .ai)
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    // MARK: - Public API

    /// Deduplicate narrative cards across all documents.
    /// Groups similar cards by heuristics, then uses LLM for intelligent merge decisions.
    func deduplicateCards(_ cards: [KnowledgeCard]) async throws -> DeduplicationResult {
        guard !cards.isEmpty else {
            return DeduplicationResult(cards: [], mergeLog: [])
        }

        // Step 1: Pre-cluster by heuristics to reduce LLM calls
        let clusters = clusterCards(cards)
        Logger.info("🔀 Clustered \(cards.count) cards into \(clusters.count) groups", category: .ai)

        // Step 2: Process each cluster
        var results: [KnowledgeCard] = []
        var mergeLog: [MergeLogEntry] = []

        for cluster in clusters {
            if cluster.cards.count == 1 {
                // Singleton - no merge needed
                results.append(cluster.cards[0])
                mergeLog.append(MergeLogEntry(
                    action: .kept,
                    inputCards: [cluster.cards[0].title],
                    outputCard: cluster.cards[0].title,
                    reasoning: "Single card in cluster"
                ))
            } else {
                // Multi-card cluster - send to LLM
                let (processed, logEntries) = try await processCluster(cluster)
                results.append(contentsOf: processed)
                mergeLog.append(contentsOf: logEntries)
            }
        }

        Logger.info("🔀 Deduplication complete: \(cards.count) → \(results.count) cards", category: .ai)
        return DeduplicationResult(cards: results, mergeLog: mergeLog)
    }

    // MARK: - Clustering

    private func clusterCards(_ cards: [KnowledgeCard]) -> [CardCluster] {
        var clusters: [CardCluster] = []
        var assigned = Set<UUID>()

        let sorted = cards.sorted { $0.title.lowercased() < $1.title.lowercased() }

        for card in sorted {
            guard !assigned.contains(card.id) else { continue }

            var clusterCards = [card]
            assigned.insert(card.id)

            for other in sorted where !assigned.contains(other.id) {
                if shouldCluster(card, other) {
                    clusterCards.append(other)
                    assigned.insert(other.id)
                }
            }

            let reason = determineClusterReason(clusterCards)
            clusters.append(CardCluster(cards: clusterCards, clusterReason: reason))
        }

        return clusters
    }

    private func shouldCluster(_ a: KnowledgeCard, _ b: KnowledgeCard) -> Bool {
        // Same card type required for merge consideration
        guard a.cardType == b.cardType else { return false }

        // 1. Exact title match (normalized)
        if normalizeTitle(a.title) == normalizeTitle(b.title) {
            return true
        }

        // 2. Same organization + overlapping time period
        if let orgA = a.organization, let orgB = b.organization,
           normalizeOrg(orgA) == normalizeOrg(orgB),
           timePeriodsOverlap(a.dateRange, b.dateRange) {
            return true
        }

        // 3. High title similarity (Jaccard on significant words > 0.6)
        if titleSimilarity(a.title, b.title) > 0.6 {
            return true
        }

        // 4. Same org + high domain overlap
        if let orgA = a.organization, let orgB = b.organization,
           normalizeOrg(orgA) == normalizeOrg(orgB),
           domainOverlap(a.extractable.domains, b.extractable.domains) > 0.5 {
            return true
        }

        return false
    }

    private func normalizeTitle(_ title: String) -> String {
        // Remove common prefixes/suffixes, normalize whitespace, lowercase
        var normalized = title.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove section numbers like "(PHYS 204A_05_01)"
        let sectionPattern = #"\s*\([^)]*_\d+_\d+\)"#
        if let regex = try? NSRegularExpression(pattern: sectionPattern) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, range: range, withTemplate: "")
        }

        return normalized
    }

    private func normalizeOrg(_ org: String) -> String {
        org.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "university", with: "univ")
            .replacingOccurrences(of: "california state", with: "csu")
    }

    private func timePeriodsOverlap(_ a: String?, _ b: String?) -> Bool {
        guard let aRange = a, let bRange = b else { return false }

        // Extract years from date strings like "2017-2018" or "2015-present"
        let yearPattern = #"(\d{4})"#
        guard let regex = try? NSRegularExpression(pattern: yearPattern) else { return false }

        func extractYears(_ s: String) -> [Int] {
            let range = NSRange(s.startIndex..., in: s)
            return regex.matches(in: s, range: range).compactMap { match in
                if let yearRange = Range(match.range(at: 1), in: s) {
                    return Int(s[yearRange])
                }
                return nil
            }
        }

        let aYears = extractYears(aRange)
        let bYears = extractYears(bRange)

        guard !aYears.isEmpty, !bYears.isEmpty else { return false }

        let aMin = aYears.min()!
        let aMax = aYears.max()!
        let bMin = bYears.min()!
        let bMax = bYears.max()!

        // Ranges overlap if one doesn't end before the other starts
        return !(aMax < bMin || bMax < aMin)
    }

    private func titleSimilarity(_ a: String, _ b: String) -> Double {
        let stopWords: Set<String> = ["the", "a", "an", "at", "in", "of", "for", "and", "or", "to"]

        func significantWords(_ s: String) -> Set<String> {
            Set(s.lowercased()
                .components(separatedBy: .alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) })
        }

        let aWords = significantWords(a)
        let bWords = significantWords(b)

        guard !aWords.isEmpty || !bWords.isEmpty else { return 0.0 }

        let intersection = aWords.intersection(bWords).count
        let union = aWords.union(bWords).count

        return Double(intersection) / Double(union)
    }

    private func domainOverlap(_ a: [String], _ b: [String]) -> Double {
        let aSet = Set(a.map { $0.lowercased() })
        let bSet = Set(b.map { $0.lowercased() })

        guard !aSet.isEmpty || !bSet.isEmpty else { return 0.0 }

        let intersection = aSet.intersection(bSet).count
        let union = aSet.union(bSet).count

        return Double(intersection) / Double(union)
    }

    private func determineClusterReason(_ cards: [KnowledgeCard]) -> ClusterReason {
        guard cards.count > 1 else { return .exactTitleMatch }

        let first = cards[0]
        let second = cards[1]

        if normalizeTitle(first.title) == normalizeTitle(second.title) {
            return .exactTitleMatch
        }

        if titleSimilarity(first.title, second.title) > 0.6 {
            return .similarTitle
        }

        if let orgA = first.organization, let orgB = second.organization,
           normalizeOrg(orgA) == normalizeOrg(orgB) {
            if timePeriodsOverlap(first.dateRange, second.dateRange) {
                return .overlappingTimePeriod
            }
            return .sameOrgAndType
        }

        return .semanticOverlap
    }

    // MARK: - LLM Processing

    private func processCluster(_ cluster: CardCluster) async throws -> ([KnowledgeCard], [MergeLogEntry]) {
        guard let facade = llmFacade else {
            throw DeduplicationError.llmNotConfigured
        }

        let prompt = buildPrompt(for: cluster)

        Logger.info("🔀 Processing cluster (\(cluster.cards.count) cards): \(cluster.cards.map { $0.title }.joined(separator: " | "))", category: .ai)

        let jsonString = try await facade.generateStructuredJSON(
            prompt: prompt,
            modelId: modelId,
            maxOutputTokens: 32768,
            jsonSchema: Self.jsonSchema
        )

        guard let data = jsonString.data(using: .utf8) else {
            throw DeduplicationError.invalidResponse
        }

        let response = try JSONDecoder().decode(MergeDecisionResponse.self, from: data)
        return applyMergeDecision(response, originalCards: cluster.cards)
    }

    private func buildPrompt(for cluster: CardCluster) -> String {
        let cardsJSON = formatCardsAsJSON(cluster.cards)
        return PromptLibrary.substitute(
            template: PromptLibrary.narrativeDedupeTemplate,
            replacements: ["CARDS_JSON": cardsJSON]
        )
    }

    private func formatCardsAsJSON(_ cards: [KnowledgeCard]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cards),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func applyMergeDecision(
        _ decision: MergeDecisionResponse,
        originalCards: [KnowledgeCard]
    ) -> ([KnowledgeCard], [MergeLogEntry]) {
        var results: [KnowledgeCard] = []
        var logEntries: [MergeLogEntry] = []

        switch decision.decision {
        case .keepSeparate:
            results = originalCards
            logEntries.append(MergeLogEntry(
                action: .keptSeparate,
                inputCards: originalCards.map { $0.title },
                outputCard: nil,
                reasoning: decision.reasoning
            ))

        case .mergeAll:
            if let merged = decision.mergedCard {
                results = [merged]
                logEntries.append(MergeLogEntry(
                    action: .merged,
                    inputCards: originalCards.map { $0.title },
                    outputCard: merged.title,
                    reasoning: decision.reasoning
                ))
            } else {
                results = originalCards
                logEntries.append(MergeLogEntry(
                    action: .error,
                    inputCards: originalCards.map { $0.title },
                    outputCard: nil,
                    reasoning: "MERGE_ALL decision but no merged_card provided"
                ))
            }

        case .mergeSubsets:
            var usedIds = Set<UUID>()

            for group in decision.mergeGroups ?? [] {
                let merged = group.mergedCard
                results.append(merged)
                let groupCardIds = Set(group.originalCardIds.compactMap { UUID(uuidString: $0) })
                usedIds.formUnion(groupCardIds)

                let inputTitles = originalCards
                    .filter { groupCardIds.contains($0.id) }
                    .map { $0.title }

                logEntries.append(MergeLogEntry(
                    action: .merged,
                    inputCards: inputTitles,
                    outputCard: merged.title,
                    reasoning: decision.reasoning
                ))
            }

            // Add cards not in any merge group
            for card in originalCards where !usedIds.contains(card.id) {
                results.append(card)
                logEntries.append(MergeLogEntry(
                    action: .kept,
                    inputCards: [card.title],
                    outputCard: card.title,
                    reasoning: "Not included in any merge group"
                ))
            }
        }

        return (results, logEntries)
    }

    // MARK: - JSON Schema

    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "decision": [
                "type": "string",
                "enum": ["KEEP_SEPARATE", "MERGE_ALL", "MERGE_SUBSETS"],
                "description": "The merge decision"
            ],
            "reasoning": [
                "type": "string",
                "description": "Explanation for the decision"
            ],
            "merged_card": [
                "type": "object",
                "description": "Present only if decision is MERGE_ALL",
                "properties": [
                    "id": ["type": "string"],
                    "card_type": [
                        "type": "string",
                        "enum": ["employment", "project", "achievement", "education"]
                    ],
                    "title": ["type": "string"],
                    "narrative": ["type": "string"],
                    "organization": ["type": "string"],
                    "date_range": ["type": "string"],
                    "evidence_anchors": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "document_id": ["type": "string"],
                                "location": ["type": "string"],
                                "verbatim_excerpt": ["type": "string"]
                            ]
                        ]
                    ],
                    "extractable": [
                        "type": "object",
                        "properties": [
                            "domains": ["type": "array", "items": ["type": "string"]],
                            "scale": ["type": "array", "items": ["type": "string"]],
                            "keywords": ["type": "array", "items": ["type": "string"]]
                        ]
                    ],
                    "verbatim_excerpts": ["type": "array", "items": ["type": "string"]],
                    "related_card_ids": ["type": "array", "items": ["type": "string"]]
                ]
            ],
            "merge_groups": [
                "type": "array",
                "description": "Present only if decision is MERGE_SUBSETS",
                "items": [
                    "type": "object",
                    "properties": [
                        "original_card_ids": [
                            "type": "array",
                            "items": ["type": "string"]
                        ],
                        "merged_card": [
                            "type": "object",
                            "properties": [
                                "id": ["type": "string"],
                                "card_type": [
                                    "type": "string",
                                    "enum": ["employment", "project", "achievement", "education"]
                                ],
                                "title": ["type": "string"],
                                "narrative": ["type": "string"],
                                "organization": ["type": "string"],
                                "date_range": ["type": "string"],
                                "evidence_anchors": [
                                    "type": "array",
                                    "items": [
                                        "type": "object",
                                        "properties": [
                                            "document_id": ["type": "string"],
                                            "location": ["type": "string"],
                                            "verbatim_excerpt": ["type": "string"]
                                        ]
                                    ]
                                ],
                                "extractable": [
                                    "type": "object",
                                    "properties": [
                                        "domains": ["type": "array", "items": ["type": "string"]],
                                        "scale": ["type": "array", "items": ["type": "string"]],
                                        "keywords": ["type": "array", "items": ["type": "string"]]
                                    ]
                                ],
                                "verbatim_excerpts": ["type": "array", "items": ["type": "string"]],
                                "related_card_ids": ["type": "array", "items": ["type": "string"]]
                            ]
                        ]
                    ]
                ]
            ]
        ],
        "required": ["decision", "reasoning"]
    ]

    enum DeduplicationError: Error, LocalizedError {
        case llmNotConfigured
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured: return "LLM facade not configured"
            case .invalidResponse: return "Invalid response from LLM"
            }
        }
    }
}

// MARK: - Supporting Types

struct DeduplicationResult {
    let cards: [KnowledgeCard]
    let mergeLog: [MergeLogEntry]
}

struct MergeLogEntry {
    enum Action: String {
        case kept
        case keptSeparate
        case merged
        case error
    }

    let action: Action
    let inputCards: [String]
    let outputCard: String?
    let reasoning: String
}

struct CardCluster {
    let cards: [KnowledgeCard]
    let clusterReason: ClusterReason
}

enum ClusterReason: String, Codable {
    case exactTitleMatch
    case similarTitle
    case sameOrgAndType
    case overlappingTimePeriod
    case semanticOverlap
}

struct MergeDecisionResponse: Codable {
    let decision: MergeDecision
    let reasoning: String
    let mergedCard: KnowledgeCard?
    let mergeGroups: [MergeGroup]?

    enum CodingKeys: String, CodingKey {
        case decision
        case reasoning
        case mergedCard = "merged_card"
        case mergeGroups = "merge_groups"
    }
}

enum MergeDecision: String, Codable {
    case keepSeparate = "KEEP_SEPARATE"
    case mergeAll = "MERGE_ALL"
    case mergeSubsets = "MERGE_SUBSETS"
}

struct MergeGroup: Codable {
    let originalCardIds: [String]
    let mergedCard: KnowledgeCard

    enum CodingKeys: String, CodingKey {
        case originalCardIds = "original_card_ids"
        case mergedCard = "merged_card"
    }
}
