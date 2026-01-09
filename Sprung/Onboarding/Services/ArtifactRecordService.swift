//
//  ArtifactRecordService.swift
//  Sprung
//
//  Service for artifact record operations that involve business logic.
//  Keeps ArtifactRecord as a pure data model.
//

import Foundation

/// Service for artifact record operations that involve business logic.
/// Keeps ArtifactRecord as a pure data model.
enum ArtifactRecordService {

    // MARK: - Folder Naming

    /// Generates a filesystem-safe folder name for an artifact.
    /// Sanitizes the display name by removing/replacing invalid characters.
    static func folderName(for record: ArtifactRecord) -> String {
        let baseName: String
        if !record.filename.isEmpty {
            let nameWithoutExt = URL(fileURLWithPath: record.filename).deletingPathExtension().lastPathComponent
            baseName = nameWithoutExt.isEmpty ? record.filename : nameWithoutExt
        } else {
            baseName = record.id.uuidString
        }
        return baseName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    // MARK: - Token Estimation

    /// Estimates tokens for arbitrary content string.
    /// Uses a simple heuristic of ~4 characters per token for English.
    static func estimateTokens(for content: String) -> Int {
        max(1, content.count / 4)
    }

    /// Estimates the token count for an artifact's extracted content.
    static func estimateExtractedContentTokens(for record: ArtifactRecord) -> Int {
        estimateTokens(for: record.extractedContent)
    }

    /// Estimates the token count for an artifact's summary.
    static func estimateSummaryTokens(for record: ArtifactRecord) -> Int {
        guard let summary = record.summary, !summary.isEmpty else { return 0 }
        return estimateTokens(for: summary)
    }

    // MARK: - Classification

    /// Determines if an artifact is a writing sample based on metadata and type.
    static func isWritingSample(_ record: ArtifactRecord) -> Bool {
        // Check source type
        if record.sourceType == "writing_sample" {
            return true
        }
        // Check document_type in metadata
        if let docType = record.metadataString("document_type") {
            if docType == "writingSample" || docType == "writing_sample" {
                return true
            }
        }
        // Check for writing_type in metadata
        if record.metadataString("writing_type") != nil {
            return true
        }
        return false
    }

    // MARK: - Data Extraction

    /// Extracts skills from artifact metadata.
    /// Returns nil if metadata doesn't contain skills or parsing fails.
    static func extractSkills(from record: ArtifactRecord) -> [Skill]? {
        guard let jsonString = record.skillsJSON,
              let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([Skill].self, from: data)
        } catch {
            Logger.warning("Failed to decode skills for \(record.filename): \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    /// Extracts narrative cards from artifact metadata.
    /// Returns nil if metadata doesn't contain cards or parsing fails.
    static func extractNarrativeCards(from record: ArtifactRecord) -> [KnowledgeCard]? {
        guard let jsonString = record.narrativeCardsJSON,
              let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([KnowledgeCard].self, from: data)
        } catch {
            Logger.warning("Failed to decode narrative cards for \(record.filename): \(error.localizedDescription)", category: .ai)
            return nil
        }
    }
}
