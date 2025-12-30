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

        Logger.info("🔄 CardMergeService: Checking \(artifacts.artifactRecords.count) artifacts for card_inventory", category: .ai)

        for artifact in artifacts.artifactRecords {
            let artifactId = artifact["id"].stringValue
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

        Logger.info("🔄 Merging \(inventories.count) document inventories", category: .ai)

        // Call LLM with schema for guaranteed JSON structure
        // Model configured in Settings - requires 65K output tokens (use Gemini 2.5+)
        let mergeModelId = UserDefaults.standard.string(forKey: "onboardingCardMergeModelId") ?? "gemini-2.5-flash"
        let jsonString = try await facade.generateStructuredJSON(
            prompt: prompt,
            modelId: mergeModelId,
            jsonSchema: CardMergePrompts.jsonSchema
        )

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw CardMergeError.invalidResponse
        }

        // Don't use .convertFromSnakeCase - MergedCardInventory has explicit CodingKeys
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let mergedInventory = try decoder.decode(MergedCardInventory.self, from: jsonData)
            Logger.info("✅ Merged inventory: \(mergedInventory.mergedCards.count) cards from \(inventories.count) documents", category: .ai)
            return mergedInventory
        } catch {
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    Logger.error("❌ Missing key '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
                case .typeMismatch(let type, let context):
                    Logger.error("❌ Type mismatch for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
                case .valueNotFound(let type, let context):
                    Logger.error("❌ Value not found for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
                case .dataCorrupted(let context):
                    Logger.error("❌ Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
                    Logger.error("   Underlying: \(context.underlyingError?.localizedDescription ?? "none")", category: .ai)
                @unknown default:
                    Logger.error("❌ Unknown decoding error: \(error.localizedDescription)", category: .ai)
                }
            }
            Logger.error("❌ Failed to decode merged inventory JSON: \(error.localizedDescription)", category: .ai)
            Logger.error("📦 Raw merge JSON (first 1000 chars): \(jsonString.prefix(1000))", category: .ai)
            // Save full JSON to file for inspection
            let logsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Sprung")
            if let logsDir = logsDir {
                let debugFile = logsDir.appendingPathComponent("failed_merge_\(UUID().uuidString.prefix(8)).json")
                try? jsonString.write(to: debugFile, atomically: true, encoding: .utf8)
                Logger.error("📦 Full JSON saved to: \(debugFile.path)", category: .ai)
            }
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
