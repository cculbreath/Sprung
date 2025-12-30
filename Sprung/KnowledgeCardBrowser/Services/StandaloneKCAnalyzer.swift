//
//  StandaloneKCAnalyzer.swift
//  Sprung
//
//  Handles document analysis, inventory creation, merging, and ResRef matching
//  for standalone KC generation. This module determines what cards should be
//  created vs which existing cards should be enhanced.
//

import Foundation
import SwiftyJSON

/// Handles document analysis and card proposal generation.
@MainActor
class StandaloneKCAnalyzer {
    // MARK: - Dependencies

    private var inventoryService: CardInventoryService?
    private var metadataService: MetadataExtractionService?
    private weak var resRefStore: ResRefStore?

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, resRefStore: ResRefStore?) {
        self.resRefStore = resRefStore
        self.inventoryService = CardInventoryService(llmFacade: llmFacade)
        self.metadataService = MetadataExtractionService(llmFacade: llmFacade)
    }

    // MARK: - Public API

    /// Analyze artifacts to generate card proposals.
    /// - Parameter artifacts: Extracted artifact JSON objects
    /// - Returns: Merged card inventory with proposals
    func analyzeArtifacts(_ artifacts: [JSON]) async throws -> MergedCardInventory {
        var inventories: [DocumentInventory] = []

        for artifact in artifacts {
            let docId = artifact["id"].stringValue
            let filename = artifact["filename"].stringValue
            let content = artifact["extracted_text"].stringValue

            // Inventory the document for potential cards
            if let service = inventoryService {
                do {
                    let inventory = try await service.inventoryDocument(
                        documentId: docId,
                        filename: filename,
                        content: content
                    )
                    inventories.append(inventory)
                } catch {
                    Logger.warning("⚠️ StandaloneKCAnalyzer: Failed to inventory \(filename): \(error.localizedDescription)", category: .ai)
                }
            }
        }

        return mergeInventoriesLocally(inventories)
    }

    /// Match proposals against existing ResRefs to determine new vs enhancement.
    /// - Parameter merged: Merged card inventory
    /// - Returns: Tuple of new cards and enhancement proposals
    func matchAgainstExisting(
        _ merged: MergedCardInventory
    ) -> (newCards: [MergedCardInventory.MergedCard], enhancements: [(proposal: MergedCardInventory.MergedCard, existing: ResRef)]) {
        let existingCards = resRefStore?.resRefs ?? []
        var newCards: [MergedCardInventory.MergedCard] = []
        var enhancements: [(proposal: MergedCardInventory.MergedCard, existing: ResRef)] = []

        for proposal in merged.mergedCards {
            if let match = findMatchingResRef(proposal, in: existingCards) {
                enhancements.append((proposal, match))
            } else {
                newCards.append(proposal)
            }
        }

        return (newCards, enhancements)
    }

    /// Extract metadata from artifacts for single-card generation.
    /// - Parameter artifacts: Extracted artifact JSON objects
    /// - Returns: Card metadata
    func extractMetadata(from artifacts: [JSON]) async throws -> CardMetadata {
        guard let service = metadataService else {
            let filename = artifacts.first?["filename"].stringValue ?? "Document"
            return CardMetadata.defaults(fromFilename: filename)
        }

        return try await service.extract(from: artifacts)
    }

    /// Enhance an existing ResRef with new evidence from a proposal.
    /// Uses fact-based merging: combines facts, bullets, and technologies.
    func enhanceResRef(_ resRef: ResRef, with proposal: MergedCardInventory.MergedCard) {
        // Merge suggested bullets
        var existingBullets: [String] = []
        if let bulletsJSON = resRef.suggestedBulletsJSON,
           let data = bulletsJSON.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String] {
            existingBullets = decoded
        }

        // Add new key facts as bullets if not already present
        let newBullets = proposal.combinedKeyFacts.filter { fact in
            !existingBullets.contains { $0.lowercased().contains(fact.lowercased().prefix(30)) }
        }
        existingBullets.append(contentsOf: newBullets)

        if let data = try? JSONSerialization.data(withJSONObject: existingBullets),
           let jsonString = String(data: data, encoding: .utf8) {
            resRef.suggestedBulletsJSON = jsonString
        }

        // Merge technologies
        var existingTech: [String] = []
        if let techJSON = resRef.technologiesJSON,
           let data = techJSON.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String] {
            existingTech = decoded
        }

        let newTech = proposal.combinedTechnologies.filter { tech in
            !existingTech.contains { $0.lowercased() == tech.lowercased() }
        }
        existingTech.append(contentsOf: newTech)

        if let data = try? JSONSerialization.data(withJSONObject: existingTech),
           let jsonString = String(data: data, encoding: .utf8) {
            resRef.technologiesJSON = jsonString
        }

        // Update content to reflect new bullets
        resRef.content = existingBullets.map { "• \($0)" }.joined(separator: "\n")

        // Update sources JSON
        var existingSources: [[String: String]] = []
        if let sourcesJSON = resRef.sourcesJSON,
           let data = sourcesJSON.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            existingSources = decoded
        }

        // Add new sources
        let existingIds = Set(existingSources.compactMap { $0["artifact_id"] })
        if !existingIds.contains(proposal.primarySource.documentId) {
            existingSources.append(["type": "artifact", "artifact_id": proposal.primarySource.documentId])
        }
        for source in proposal.supportingSources where !existingIds.contains(source.documentId) {
            existingSources.append(["type": "artifact", "artifact_id": source.documentId])
        }

        if let data = try? JSONSerialization.data(withJSONObject: existingSources),
           let jsonString = String(data: data, encoding: .utf8) {
            resRef.sourcesJSON = jsonString
        }

        resRefStore?.updateResRef(resRef)
        Logger.info("✅ StandaloneKCAnalyzer: Enhanced card with \(newBullets.count) new facts, \(newTech.count) new technologies", category: .ai)
    }

    // MARK: - Private: Inventory Merging

    /// Simple local merge of inventories without LLM (for standalone use)
    private func mergeInventoriesLocally(_ inventories: [DocumentInventory]) -> MergedCardInventory {
        var mergedCards: [MergedCardInventory.MergedCard] = []
        var cardsByKey: [String: MergedCardInventory.MergedCard] = [:]

        for inventory in inventories {
            for proposed in inventory.proposedCards {
                // Create a key for grouping similar cards
                let key = "\(proposed.cardType.rawValue):\(proposed.proposedTitle.lowercased())"

                if var existing = cardsByKey[key] {
                    // Merge into existing card
                    var combinedFacts = existing.combinedKeyFacts
                    combinedFacts.append(contentsOf: proposed.keyFacts.filter { !combinedFacts.contains($0) })

                    var combinedTech = existing.combinedTechnologies
                    combinedTech.append(contentsOf: proposed.technologies.filter { !combinedTech.contains($0) })

                    var combinedOutcomes = existing.combinedOutcomes
                    combinedOutcomes.append(contentsOf: proposed.quantifiedOutcomes.filter { !combinedOutcomes.contains($0) })

                    var supportingSources = existing.supportingSources
                    supportingSources.append(MergedCardInventory.MergedCard.SupportingSource(
                        documentId: inventory.documentId,
                        evidenceLocations: proposed.evidenceLocations,
                        adds: proposed.keyFacts
                    ))

                    existing = MergedCardInventory.MergedCard(
                        cardId: existing.cardId,
                        cardType: existing.cardType,
                        title: existing.title,
                        primarySource: existing.primarySource,
                        supportingSources: supportingSources,
                        combinedKeyFacts: combinedFacts,
                        combinedTechnologies: combinedTech,
                        combinedOutcomes: combinedOutcomes,
                        dateRange: existing.dateRange ?? proposed.dateRange,
                        evidenceQuality: .strong,
                        extractionPriority: .high
                    )
                    cardsByKey[key] = existing
                } else {
                    // Create new merged card
                    let merged = MergedCardInventory.MergedCard(
                        cardId: UUID().uuidString,
                        cardType: proposed.cardType.rawValue,
                        title: proposed.proposedTitle,
                        primarySource: MergedCardInventory.MergedCard.SourceReference(
                            documentId: inventory.documentId,
                            evidenceLocations: proposed.evidenceLocations
                        ),
                        supportingSources: [],
                        combinedKeyFacts: proposed.keyFacts,
                        combinedTechnologies: proposed.technologies,
                        combinedOutcomes: proposed.quantifiedOutcomes,
                        dateRange: proposed.dateRange,
                        evidenceQuality: proposed.evidenceStrength == .primary ? .strong : .moderate,
                        extractionPriority: .high
                    )
                    cardsByKey[key] = merged
                }
            }
        }

        mergedCards = Array(cardsByKey.values)

        let grouped = Dictionary(grouping: mergedCards, by: { $0.cardType })
        return MergedCardInventory(
            mergedCards: mergedCards,
            gaps: [],
            stats: MergedCardInventory.MergeStats(
                totalInputCards: inventories.flatMap { $0.proposedCards }.count,
                mergedOutputCards: mergedCards.count,
                cardsByType: MergedCardInventory.MergeStats.CardsByType(
                    employment: grouped["employment"]?.count ?? 0,
                    project: grouped["project"]?.count ?? 0,
                    skill: grouped["skill"]?.count ?? 0,
                    achievement: grouped["achievement"]?.count ?? 0,
                    education: grouped["education"]?.count ?? 0
                ),
                strongEvidence: mergedCards.filter { $0.evidenceQuality == .strong }.count,
                needsMoreEvidence: mergedCards.filter { $0.evidenceQuality == .weak }.count
            ),
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Private: ResRef Matching

    /// Match a proposal against existing ResRefs
    private func findMatchingResRef(
        _ proposal: MergedCardInventory.MergedCard,
        in existing: [ResRef]
    ) -> ResRef? {
        let titleCore = proposalTitleCore(proposal.title)
        return existing.first { resRef in
            resRef.cardType == proposal.cardType &&
            resRef.name.lowercased().contains(titleCore)
        }
    }

    /// Extract core identifier from title (e.g., "Senior Engineer at TechCorp" -> "techcorp")
    private func proposalTitleCore(_ title: String) -> String {
        title.lowercased().split(separator: " ").last.map(String.init) ?? title.lowercased()
    }
}
