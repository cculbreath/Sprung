//
//  DataResetService.swift
//  Sprung
//
//  Service responsible for coordinating a complete data reset across all stores and persistent layers.
//
import Foundation
import SwiftData

@Observable
@MainActor
final class DataResetService {
    // MARK: - Properties
    var isResetting: Bool = false
    var resetError: String?

    // MARK: - Granular Reset Methods

    /// Clear all artifact records from SwiftData
    /// - Parameter context: SwiftData ModelContext
    /// - Returns: Number of records deleted
    @discardableResult
    func clearArtifactRecords(context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<ArtifactRecord>()
        let artifacts = (try? context.fetch(descriptor)) ?? []
        let count = artifacts.count

        for artifact in artifacts {
            context.delete(artifact)
        }

        try context.save()
        Logger.info("Cleared \(count) artifact records", category: .appLifecycle)
        return count
    }

    /// Clear all knowledge cards from SwiftData
    /// - Parameter context: SwiftData ModelContext
    /// - Returns: Number of records deleted
    @discardableResult
    func clearKnowledgeCards(context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<KnowledgeCard>()
        let cards = (try? context.fetch(descriptor)) ?? []
        let count = cards.count

        for card in cards {
            context.delete(card)
        }

        try context.save()
        Logger.info("Cleared \(count) knowledge cards", category: .appLifecycle)
        return count
    }

    /// Clear all writing samples from SwiftData
    /// Writing samples are CoverRef objects with type == .writingSample
    /// - Parameter context: SwiftData ModelContext
    /// - Returns: Number of records deleted
    @discardableResult
    func clearWritingSamples(context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<CoverRef>()
        let allRefs = (try? context.fetch(descriptor)) ?? []
        let writingSamples = allRefs.filter { $0.type == .writingSample }
        let count = writingSamples.count

        for sample in writingSamples {
            context.delete(sample)
        }

        try context.save()
        Logger.info("🗑️ Cleared \(count) writing samples", category: .appLifecycle)
        return count
    }

    /// Clear all skills from SwiftData
    /// - Parameter context: SwiftData ModelContext
    /// - Returns: Number of records deleted
    @discardableResult
    func clearSkills(context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Skill>()
        let skills = (try? context.fetch(descriptor)) ?? []
        let count = skills.count

        for skill in skills {
            context.delete(skill)
        }

        try context.save()
        Logger.info("Cleared \(count) skills", category: .appLifecycle)
        return count
    }

    /// Clear all title sets from SwiftData
    /// - Parameter context: SwiftData ModelContext
    /// - Returns: Number of records deleted
    @discardableResult
    func clearTitleSets(context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<TitleSetRecord>()
        let titleSets = (try? context.fetch(descriptor)) ?? []
        let count = titleSets.count

        for titleSet in titleSets {
            context.delete(titleSet)
        }

        try context.save()
        Logger.info("Cleared \(count) title sets", category: .appLifecycle)
        return count
    }

    /// Clear all candidate dossiers from SwiftData
    /// - Parameter context: SwiftData ModelContext
    /// - Returns: Number of records deleted
    @discardableResult
    func clearDossiers(context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<CandidateDossier>()
        let dossiers = (try? context.fetch(descriptor)) ?? []
        let count = dossiers.count

        for dossier in dossiers {
            context.delete(dossier)
        }

        try context.save()
        Logger.info("Cleared \(count) dossiers", category: .appLifecycle)
        return count
    }

    /// Reset all onboarding-generated data: knowledge cards, writing samples, skills, title sets, and dossiers
    /// - Parameter context: SwiftData ModelContext
    /// - Returns: Summary message of what was cleared
    func resetOnboarding(context: ModelContext) throws -> String {
        let kcCount = try clearKnowledgeCards(context: context)
        let wsCount = try clearWritingSamples(context: context)
        let skillCount = try clearSkills(context: context)
        let tsCount = try clearTitleSets(context: context)
        let dossierCount = try clearDossiers(context: context)

        let summary = "Cleared \(kcCount) knowledge cards, \(wsCount) writing samples, \(skillCount) skills, \(tsCount) title sets, \(dossierCount) dossiers"
        Logger.info("Onboarding reset: \(summary)", category: .appLifecycle)
        return summary
    }

    // MARK: - Reset Orchestration
    /// Performs a complete factory reset of all application data.
    /// Marks SwiftData store for deletion on next launch (avoids SQLite relationship constraint errors),
    /// clears UserDefaults, and removes file-based storage.
    func performFactoryReset() async throws {
        isResetting = true
        resetError = nil
        defer { isResetting = false }
        do {
            // Mark SwiftData store for deletion on next launch.
            // This avoids SQLite relationship constraint errors from batch delete.
            try SwiftDataBackupManager.destroyCurrentStore()
            resetAPIKeys()
            resetUserDefaults()
            try resetFileBasedStorage()
            Logger.info("✅ Factory reset scheduled - data will be cleared on restart", category: .appLifecycle)
        } catch {
            resetError = error.localizedDescription
            Logger.error("❌ Factory reset failed: \(error)", category: .appLifecycle)
            throw error
        }
    }
    // MARK: - Private Reset Methods
    private func resetAPIKeys() {
        APIKeyManager.delete(.openRouter)
        APIKeyManager.delete(.openAI)
        APIKeyManager.delete(.gemini)
        Logger.debug("✅ API keys cleared from Keychain", category: .appLifecycle)
    }

    private func resetUserDefaults() {
        let defaults = UserDefaults.standard

        // Reset setup wizard flag to trigger first-run experience
        defaults.removeObject(forKey: "hasCompletedSetupWizard")

        // Reset onboarding interview settings
        defaults.removeObject(forKey: "onboardingInterviewDefaultModelId")
        defaults.removeObject(forKey: "onboardingPDFExtractionModelId")
        defaults.removeObject(forKey: "onboardingGitIngestModelId")
        defaults.removeObject(forKey: "onboardingInterviewAllowWebSearchDefault")
        defaults.removeObject(forKey: "onboardingInterviewReasoningEffort")
        defaults.removeObject(forKey: "onboardingInterviewHardTaskReasoningEffort")
        defaults.removeObject(forKey: "onboardingInterviewFlexProcessing")
        defaults.removeObject(forKey: "onboardingInterviewPromptCacheRetention")

        // Reset resume/cover letter AI settings
        defaults.removeObject(forKey: "reasoningEffort")
        defaults.removeObject(forKey: "fixOverflowMaxIterations")
        defaults.removeObject(forKey: "enableResumeCustomizationTools")
        defaults.removeObject(forKey: "enableCoherencePass")

        // Reset debug settings
        defaults.removeObject(forKey: "debugLogLevel")
        defaults.removeObject(forKey: "saveDebugPrompts")
        defaults.removeObject(forKey: "showOnboardingDebugButton")

        // Reset other app state
        defaults.removeObject(forKey: "lastOpenedJobAppId")

        Logger.debug("✅ UserDefaults reset", category: .appLifecycle)
    }
    private func resetFileBasedStorage() throws {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Reset Onboarding data directory
        let onboardingDataURL = appSupportURL.appendingPathComponent("Onboarding/Data", isDirectory: true)
        if fileManager.fileExists(atPath: onboardingDataURL.path) {
            try fileManager.removeItem(at: onboardingDataURL)
            Logger.debug("✅ Onboarding data directory reset", category: .appLifecycle)
        }
        // Reset career keywords file
        let careerKeywordsURL = appSupportURL.appendingPathComponent("Sprung/career_keywords.json")
        if fileManager.fileExists(atPath: careerKeywordsURL.path) {
            try fileManager.removeItem(at: careerKeywordsURL)
            Logger.debug("✅ Career keywords file reset", category: .appLifecycle)
        }
        Logger.debug("✅ File-based storage reset", category: .appLifecycle)
    }
}
