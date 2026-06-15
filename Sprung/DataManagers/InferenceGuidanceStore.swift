//
//  InferenceGuidanceStore.swift
//  Sprung
//
//  CRUD store for InferenceGuidance records.
//  Provides node-specific prompting for resume customization.
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class InferenceGuidanceStore: EntityStore {
    typealias Entity = InferenceGuidance

    unowned let modelContext: ModelContext

    /// `@Observable` refresh counter bumped by EntityStore mutations.
    var changeVersion: Int = 0

    init(context: ModelContext) {
        modelContext = context
        Logger.info("InferenceGuidanceStore initialized", category: .data)
    }

    // MARK: - Computed Properties

    /// All guidance records
    var allGuidance: [InferenceGuidance] {
        fetchAll(sortBy: [SortDescriptor(\.nodeKey)])
    }

    /// Only enabled guidance
    var enabledGuidance: [InferenceGuidance] {
        allGuidance.filter { $0.isEnabled }
    }

    // MARK: - CRUD

    func update(_ guidance: InferenceGuidance) {
        guidance.updatedAt = Date()
        persistChanges()
        Logger.info("📝 Updated inference guidance: \(guidance.nodeKey)", category: .data)
    }

    func toggleEnabled(_ guidance: InferenceGuidance) {
        guidance.isEnabled.toggle()
        guidance.updatedAt = Date()
        persistChanges()
    }

    // MARK: - Queries

    /// Get guidance for a specific node key
    func guidance(for nodeKey: String) -> InferenceGuidance? {
        enabledGuidance.first { $0.nodeKey == nodeKey }
    }

    /// Get guidance matching a pattern (e.g., "experience.*" matches "experience.job1.bullets")
    func guidanceMatching(pattern: String) -> InferenceGuidance? {
        // Handle wildcard patterns like "experience.*.bullets"
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: "[^.]+")

        guard let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$") else {
            return nil
        }

        return enabledGuidance.first { guidance in
            let range = NSRange(guidance.nodeKey.startIndex..., in: guidance.nodeKey)
            return regex.firstMatch(in: guidance.nodeKey, range: range) != nil
        }
    }

    /// Get rendered prompt for a node key (returns nil if no guidance)
    func renderedPrompt(for nodeKey: String) -> String? {
        guidance(for: nodeKey)?.renderedPrompt()
    }

    // MARK: - Title Set Helpers

    /// Get title sets from custom.jobTitles guidance
    func titleSets() -> [TitleSet] {
        guard let guidance = guidance(for: "custom.jobTitles"),
              let attachments = GuidanceAttachments.from(json: guidance.attachmentsJSON) else {
            return []
        }
        return attachments.titleSets ?? []
    }

    /// Get favorited title sets
    func favoriteTitleSets() -> [TitleSet] {
        titleSets().filter { $0.isFavorite }
    }

    /// Update title sets (preserves other attachments)
    func updateTitleSets(_ sets: [TitleSet]) {
        guard let guidance = guidance(for: "custom.jobTitles") else {
            Logger.warning("⚠️ No guidance found for custom.jobTitles", category: .data)
            return
        }

        var attachments = GuidanceAttachments.from(json: guidance.attachmentsJSON) ?? GuidanceAttachments()
        attachments.titleSets = sets
        guidance.attachmentsJSON = attachments.asJSON()
        guidance.updatedAt = Date()
        persistChanges()
    }

    /// Toggle favorite status on a title set
    func toggleTitleSetFavorite(_ setId: String) {
        var sets = titleSets()
        guard let idx = sets.firstIndex(where: { $0.id == setId }) else { return }
        sets[idx].isFavorite.toggle()
        updateTitleSets(sets)
    }

    // MARK: - Voice Profile Helpers

    /// Get voice profile from objective guidance
    func voiceProfile() -> VoiceProfile? {
        guard let guidance = guidance(for: "objective"),
              let attachments = GuidanceAttachments.from(json: guidance.attachmentsJSON) else {
            return nil
        }
        return attachments.voiceProfile
    }

    /// Update voice profile
    func updateVoiceProfile(_ profile: VoiceProfile) {
        guard let guidance = guidance(for: "objective") else {
            Logger.warning("⚠️ No guidance found for objective", category: .data)
            return
        }

        var attachments = GuidanceAttachments.from(json: guidance.attachmentsJSON) ?? GuidanceAttachments()
        attachments.voiceProfile = profile
        guidance.attachmentsJSON = attachments.asJSON()
        guidance.updatedAt = Date()
        persistChanges()
    }

    // MARK: - Vocabulary Helpers

    /// Get identity vocabulary from custom.jobTitles guidance
    func identityVocabulary() -> [IdentityTerm] {
        guard let guidance = guidance(for: "custom.jobTitles"),
              let attachments = GuidanceAttachments.from(json: guidance.attachmentsJSON) else {
            return []
        }
        return attachments.vocabulary ?? []
    }

    /// Update identity vocabulary
    func updateIdentityVocabulary(_ terms: [IdentityTerm]) {
        guard let guidance = guidance(for: "custom.jobTitles") else {
            Logger.warning("⚠️ No guidance found for custom.jobTitles", category: .data)
            return
        }

        var attachments = GuidanceAttachments.from(json: guidance.attachmentsJSON) ?? GuidanceAttachments()
        attachments.vocabulary = terms
        guidance.attachmentsJSON = attachments.asJSON()
        guidance.updatedAt = Date()
        persistChanges()
    }

    // MARK: - Bulk Operations

    /// Delete all auto-generated guidance (for re-running onboarding)
    func deleteAutoGenerated() {
        let autoGuidance = allGuidance.filter { $0.source == .auto }
        deleteAll(autoGuidance)
        Logger.info("🗑️ Deleted \(autoGuidance.count) auto-generated guidance records", category: .data)
    }

    /// Check if any guidance exists
    var hasGuidance: Bool {
        !allGuidance.isEmpty
    }

    /// Check if auto-generated guidance exists
    var hasAutoGeneratedGuidance: Bool {
        allGuidance.contains { $0.source == .auto }
    }
}
