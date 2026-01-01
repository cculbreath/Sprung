//
//  MergedCardToResRefConverter.swift
//  Sprung
//
//  Converts MergedCard inventory items directly to ResRef knowledge cards.
//  Maps structured fields directly and generates a 3-5 sentence prose summary
//  via a single LLM call per card.
//

import Foundation
import SwiftyJSON

/// Converts MergedCard objects to ResRef knowledge cards.
/// Uses structured field mapping plus a single LLM call for prose summary generation.
@MainActor
final class MergedCardToResRefConverter {

    // MARK: - Settings Keys

    /// UserDefaults key for the prose summary model preference
    static let proseSummaryModelKey = "onboardingProseSummaryModel"

    /// Default model for prose summary generation (fast, cost-effective)
    static let defaultProseSummaryModel = "google/gemini-2.0-flash-001"

    // MARK: - Dependencies

    private let llmFacade: LLMFacade?
    private let eventBus: EventCoordinator?

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, eventBus: EventCoordinator? = nil) {
        self.llmFacade = llmFacade
        self.eventBus = eventBus
    }

    // MARK: - Public API

    /// Convert a MergedCard to a ResRef with structured data and prose summary.
    /// - Parameters:
    ///   - mergedCard: The merged card from card inventory merge
    ///   - artifactLookup: Mapping of artifact IDs to filenames for source attribution
    /// - Returns: A ResRef ready for persistence
    func convert(
        mergedCard: MergedCardInventory.MergedCard,
        artifactLookup: [String: String] = [:]
    ) async throws -> ResRef {
        // Generate prose summary if LLM is available
        let proseSummary: String
        if let facade = llmFacade {
            proseSummary = await generateProseSummary(for: mergedCard, using: facade)
        } else {
            // Fallback: bullet list of key facts
            proseSummary = mergedCard.keyFactStatements.map { "• \($0)" }.joined(separator: "\n")
        }

        // Build sources JSON from primary and supporting sources
        let sourcesJSON = buildSourcesJSON(mergedCard: mergedCard, artifactLookup: artifactLookup)

        // Build facts JSON from combined key facts
        let factsJSON = buildFactsJSON(keyFacts: mergedCard.combinedKeyFacts)

        // Encode technologies
        let technologiesJSON = encodeArray(mergedCard.combinedTechnologies)

        // Encode outcomes
        let outcomesJSON = encodeArray(mergedCard.combinedOutcomes)

        // Build suggested bullets from facts and outcomes
        let suggestedBullets = buildSuggestedBullets(
            facts: mergedCard.combinedKeyFacts,
            outcomes: mergedCard.combinedOutcomes
        )
        let suggestedBulletsJSON = encodeArray(suggestedBullets)

        // Create ResRef with all structured data
        let resRef = ResRef(
            name: mergedCard.title,
            content: proseSummary,
            enabledByDefault: mergedCard.evidenceQuality == .strong,
            cardType: normalizeCardType(mergedCard.cardType),
            timePeriod: mergedCard.dateRange,
            organization: extractOrganization(from: mergedCard),
            location: nil,
            sourcesJSON: sourcesJSON,
            isFromOnboarding: true,
            tokenCount: nil,
            factsJSON: factsJSON,
            suggestedBulletsJSON: suggestedBulletsJSON,
            technologiesJSON: technologiesJSON
        )

        // Set additional fields
        resRef.outcomesJSON = outcomesJSON
        resRef.evidenceQuality = mergedCard.evidenceQuality.rawValue

        return resRef
    }

    /// Convert multiple MergedCards sequentially.
    /// Note: Sequential processing is required because ResRef is a SwiftData PersistentModel
    /// which is not Sendable and cannot be passed across task boundaries.
    /// - Parameters:
    ///   - mergedCards: Array of merged cards
    ///   - artifactLookup: Mapping of artifact IDs to filenames
    ///   - onProgress: Optional callback with (completed, total)
    /// - Returns: Array of ResRefs
    func convertAll(
        mergedCards: [MergedCardInventory.MergedCard],
        artifactLookup: [String: String] = [:],
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> [ResRef] {
        let total = mergedCards.count
        var results: [ResRef] = []

        for (index, card) in mergedCards.enumerated() {
            do {
                let resRef = try await convert(mergedCard: card, artifactLookup: artifactLookup)
                results.append(resRef)
            } catch {
                Logger.error("🚨 Failed to convert card '\(card.title)': \(error)", category: .ai)
            }
            onProgress?(index + 1, total)
        }

        Logger.info("✅ Converted \(results.count)/\(total) merged cards to ResRefs", category: .ai)
        return results
    }

    // MARK: - Private Helpers

    private func generateProseSummary(
        for card: MergedCardInventory.MergedCard,
        using facade: LLMFacade
    ) async -> String {
        let modelId = UserDefaults.standard.string(forKey: Self.proseSummaryModelKey)
            ?? Self.defaultProseSummaryModel

        // Load and populate prompt template
        let template = PromptLibrary.kcProseSummary
        let prompt = PromptLibrary.substitute(
            template: template,
            replacements: [
                "CARD_TYPE": card.cardType,
                "TITLE": card.title,
                "ORGANIZATION": extractOrganization(from: card) ?? "(not specified)",
                "TIME_PERIOD": card.dateRange ?? "(not specified)",
                "KEY_FACTS": card.keyFactStatements.map { "- \($0)" }.joined(separator: "\n"),
                "TECHNOLOGIES": card.combinedTechnologies.isEmpty
                    ? "(none listed)"
                    : card.combinedTechnologies.joined(separator: ", "),
                "OUTCOMES": card.combinedOutcomes.isEmpty
                    ? "(none listed)"
                    : card.combinedOutcomes.map { "- \($0)" }.joined(separator: "\n")
            ]
        )

        do {
            let summary = try await facade.executeText(
                prompt: prompt,
                modelId: modelId,
                temperature: 0.3,
                backend: .openRouter
            )

            // Emit token usage event
            await eventBus?.publish(.llmTokenUsageReceived(
                modelId: modelId,
                inputTokens: prompt.count / 4,  // Rough estimate
                outputTokens: summary.count / 4,
                cachedTokens: 0,
                reasoningTokens: 0,
                source: .cardGeneration
            ))

            return summary.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Logger.warning("⚠️ Failed to generate prose summary for '\(card.title)': \(error)", category: .ai)
            // Fallback to bullet list
            return card.keyFactStatements.map { "• \($0)" }.joined(separator: "\n")
        }
    }

    private func buildSourcesJSON(
        mergedCard: MergedCardInventory.MergedCard,
        artifactLookup: [String: String]
    ) -> String? {
        var sources: [[String: String]] = []

        // Primary source
        let primaryId = mergedCard.primarySource.documentId
        sources.append([
            "artifact_id": primaryId,
            "filename": artifactLookup[primaryId] ?? primaryId,
            "type": "primary"
        ])

        // Supporting sources
        for supporting in mergedCard.supportingSources {
            let id = supporting.documentId
            sources.append([
                "artifact_id": id,
                "filename": artifactLookup[id] ?? id,
                "type": "supporting",
                "contributes": supporting.adds.joined(separator: "; ")
            ])
        }

        guard !sources.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: sources),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func buildFactsJSON(keyFacts: [CategorizedFact]) -> String? {
        guard !keyFacts.isEmpty else { return nil }

        // Use preserved categories from pipeline - no re-categorization needed
        let facts: [[String: Any]] = keyFacts.map { fact in
            [
                "category": fact.category.rawValue,
                "statement": fact.statement,
                "confidence": "high",
                "source": nil as Any? as Any
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: facts),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func buildSuggestedBullets(facts: [CategorizedFact], outcomes: [String]) -> [String] {
        var bullets: [String] = []

        // Prioritize quantified outcomes
        for outcome in outcomes.prefix(3) {
            bullets.append(outcome)
        }

        // Add top facts that aren't duplicated in outcomes
        let outcomeSet = Set(outcomes.map { $0.lowercased() })
        for fact in facts {
            if !outcomeSet.contains(fact.statement.lowercased()) && bullets.count < 5 {
                bullets.append(fact.statement)
            }
        }

        return bullets
    }

    private func encodeArray(_ array: [String]) -> String? {
        guard !array.isEmpty,
              let data = try? JSONEncoder().encode(array),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func normalizeCardType(_ cardType: String) -> String {
        // Normalize to standard types
        switch cardType.lowercased() {
        case "job", "employment", "work":
            return "employment"
        case "project":
            return "project"
        case "skill", "skills":
            return "skill"
        case "education", "degree":
            return "education"
        case "achievement", "award":
            return "achievement"
        default:
            return cardType.lowercased()
        }
    }

    private func extractOrganization(from card: MergedCardInventory.MergedCard) -> String? {
        // Try to extract organization from title patterns like "Senior Engineer at Acme Corp"
        let patterns = [
            #" at (.+)$"#,
            #" for (.+)$"#,
            #" with (.+)$"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: card.title, range: NSRange(card.title.startIndex..., in: card.title)),
               let range = Range(match.range(at: 1), in: card.title) {
                return String(card.title[range])
            }
        }

        return nil
    }
}
