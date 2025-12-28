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

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    /// Merge all document inventories into unified card inventory
    /// - Parameter timeline: Skeleton timeline for employment context
    /// - Returns: MergedCardInventory
    func mergeInventories(timeline: JSON?) async throws -> MergedCardInventory {
        guard let facade = llmFacade else {
            throw CardMergeError.llmNotConfigured
        }

        // Gather all document inventories from artifact records
        let artifacts = await artifactRepository.getArtifacts()
        var inventories: [DocumentInventory] = []

        for artifact in artifacts.artifactRecords {
            guard let inventoryString = artifact["card_inventory"].string,
                  let inventoryData = inventoryString.data(using: .utf8) else {
                continue
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .iso8601
                let inventory = try decoder.decode(DocumentInventory.self, from: inventoryData)
                inventories.append(inventory)
            } catch {
                Logger.warning("⚠️ Failed to decode inventory for artifact: \(artifact["id"].stringValue)", category: .ai)
            }
        }

        guard !inventories.isEmpty else {
            throw CardMergeError.noInventories
        }

        let prompt = CardMergePrompts.mergePrompt(
            inventories: inventories,
            timeline: timeline
        )

        Logger.info("🔄 Merging \(inventories.count) document inventories", category: .ai)

        // Call LLM and parse JSON response
        let jsonString = try await facade.generateStructuredJSON(prompt: prompt)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw CardMergeError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        do {
            let mergedInventory = try decoder.decode(MergedCardInventory.self, from: jsonData)
            Logger.info("✅ Merged inventory: \(mergedInventory.mergedCards.count) cards from \(inventories.count) documents", category: .ai)
            return mergedInventory
        } catch {
            Logger.error("❌ Failed to decode merged inventory JSON: \(error.localizedDescription)", category: .ai)
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
