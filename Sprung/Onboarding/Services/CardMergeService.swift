//
//  CardMergeService.swift
//  Sprung
//
//  Service for merging card inventories across documents.
//

import Foundation
import SwiftyJSON

/// Service for merging card inventories across documents
actor CardMergeService {
    private var llmFacade: LLMFacade?
    private let artifactRepository: ArtifactRepository

    init(artifactRepository: ArtifactRepository, llmFacade: LLMFacade?) {
        self.artifactRepository = artifactRepository
        self.llmFacade = llmFacade
        Logger.info("🔄 CardMergeService initialized", category: .ai)
    }

    /// Merge all document inventories into unified card inventory
    /// Uses GPT-5 with strict schema enforcement for guaranteed valid output
    /// - Parameter timeline: Skeleton timeline for employment context
    /// - Returns: MergedCardInventory
    func mergeInventories(timeline: JSON?) async throws -> MergedCardInventory {
        guard let facade = llmFacade else {
            throw CardMergeError.llmNotConfigured
        }

        // Gather all document inventories from artifact records
        let artifacts = await artifactRepository.getArtifacts()
        var inventories: [DocumentInventory] = []

        Logger.info("🔄 CardMergeService: Checking \(artifacts.artifactRecords.count) artifacts for card_inventory", category: .ai)

        for artifact in artifacts.artifactRecords {
            let filename = artifact["filename"].stringValue

            // Check what keys exist on this artifact
            let hasCardInventory = artifact["card_inventory"].exists()
            let cardInventoryType = artifact["card_inventory"].type
            Logger.info("📦 Artifact '\(filename)': card_inventory exists=\(hasCardInventory), type=\(cardInventoryType)", category: .ai)

            guard let inventoryString = artifact["card_inventory"].string,
                  let inventoryData = inventoryString.data(using: .utf8) else {
                Logger.info("⏭️ Skipping artifact '\(filename)': no card_inventory string", category: .ai)
                continue
            }

            do {
                // Don't use .convertFromSnakeCase - DocumentInventory has explicit CodingKeys
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let inventory = try decoder.decode(DocumentInventory.self, from: inventoryData)
                inventories.append(inventory)
                Logger.debug("📦 Decoded inventory for artifact: \(artifact["id"].stringValue) with \(inventory.proposedCards.count) cards", category: .ai)
            } catch {
                Logger.warning("⚠️ Failed to decode inventory for artifact: \(artifact["id"].stringValue): \(error.localizedDescription)", category: .ai)
            }
        }

        guard !inventories.isEmpty else {
            throw CardMergeError.noInventories
        }

        let prompt = CardMergePrompts.mergePrompt(
            inventories: inventories,
            timeline: timeline
        )

        Logger.info("🔄 Merging \(inventories.count) document inventories using OpenRouter", category: .ai)

        // Use OpenRouter with strict schema enforcement
        let mergeModelId = UserDefaults.standard.string(forKey: "onboardingCardMergeModelId") ?? "openai/gpt-5"

        do {
            let mergedInventory: MergedCardInventory = try await facade.executeStructuredWithSchema(
                prompt: prompt,
                modelId: mergeModelId,
                as: MergedCardInventory.self,
                schema: CardMergePrompts.openAISchema,
                schemaName: "merged_card_inventory",
                temperature: 0.2,
                backend: .openRouter
            )

            Logger.info("✅ Merged inventory: \(mergedInventory.mergedCards.count) cards from \(inventories.count) documents", category: .ai)
            return mergedInventory
        } catch {
            Logger.error("❌ Card merge failed: \(error.localizedDescription)", category: .ai)
            throw CardMergeError.invalidResponse
        }
    }

    enum CardMergeError: Error, LocalizedError {
        case llmNotConfigured
        case noInventories
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM facade is not configured"
            case .noInventories:
                return "No document inventories found to merge"
            case .invalidResponse:
                return "Invalid response from LLM"
            }
        }
    }
}
