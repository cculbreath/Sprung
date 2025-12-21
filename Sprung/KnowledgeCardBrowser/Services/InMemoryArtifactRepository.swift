//
//  InMemoryArtifactRepository.swift
//  Sprung
//
//  Lightweight in-memory implementation of ArtifactStorageProtocol for standalone
//  knowledge card generation (outside of onboarding workflow).
//
//  This allows SubAgentToolExecutor and KC agents to work without coupling
//  to the onboarding EventCoordinator or StateCoordinator.
//

import Foundation
import SwiftyJSON

/// In-memory artifact storage for standalone KC generation.
/// Ephemeral storage that doesn't persist to disk - used only during
/// the ingestion workflow to hold extracted artifacts temporarily.
actor InMemoryArtifactRepository: ArtifactStorageProtocol {
    // MARK: - Storage

    private var artifacts: [String: JSON] = [:]
    private var pendingCards: [String: JSON] = [:]

    // MARK: - ArtifactStorageProtocol

    func getArtifactRecord(id: String) async -> JSON? {
        artifacts[id]
    }

    func addArtifactRecord(_ artifact: JSON) async {
        let id = artifact["id"].stringValue
        guard !id.isEmpty else {
            Logger.warning("⚠️ InMemoryArtifactRepository: Cannot add artifact without id", category: .ai)
            return
        }
        artifacts[id] = artifact
        Logger.debug("📦 InMemoryArtifactRepository: Added artifact \(id)", category: .ai)
    }

    func storePendingCard(_ card: JSON, id: String) async {
        pendingCards[id] = card
        Logger.debug("📦 InMemoryArtifactRepository: Stored pending card \(id)", category: .ai)
    }

    func getPendingCard(id: String) async -> JSON? {
        pendingCards[id]
    }

    // MARK: - Additional Helpers

    /// Get all stored artifacts
    func getAllArtifacts() -> [JSON] {
        Array(artifacts.values)
    }

    /// Get artifact summaries for KC agent prompt building
    func getArtifactSummaries() -> [JSON] {
        artifacts.values.map { artifact in
            var summary = JSON()
            summary["id"] = artifact["id"]
            summary["filename"] = artifact["filename"]
            summary["summary"] = artifact["summary"]
            summary["brief_description"] = artifact["brief_description"]
            summary["document_type"] = artifact["summary_metadata"]["document_type"]

            // Include summary_metadata if present
            if !artifact["summary_metadata"].dictionaryValue.isEmpty {
                summary["summary_metadata"] = artifact["summary_metadata"]
            }

            return summary
        }
    }

    /// Clear all storage
    func reset() {
        artifacts.removeAll()
        pendingCards.removeAll()
        Logger.debug("🔄 InMemoryArtifactRepository: Reset", category: .ai)
    }

    /// Get count of stored artifacts
    var artifactCount: Int {
        artifacts.count
    }
}
