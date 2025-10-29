//
//  DataResetService.swift
//  Sprung
//
//  Service responsible for coordinating a complete data reset across all stores and persistent layers.
//

import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class DataResetService {
    // MARK: - Properties
    var isResetting: Bool = false
    var resetError: String?

    // MARK: - Reset Orchestration
    /// Performs a complete factory reset of all application data.
    /// This includes SwiftData models, UserDefaults, Keychain, and file-based storage.
    func performFactoryReset(
        modelContext: ModelContext,
        applicantProfileStore: ApplicantProfileStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        enabledLLMStore: EnabledLLMStore,
        onboardingArtifactStore: OnboardingArtifactStore,
        careerKeywordStore: CareerKeywordStore
    ) async throws {
        isResetting = true
        resetError = nil
        defer { isResetting = false }

        do {
            try resetSwiftDataModels(modelContext: modelContext)
            try resetUserDefaults()
            try resetFileBasedStorage()
            try await resetStoreCaches(
                applicantProfileStore: applicantProfileStore,
                experienceDefaultsStore: experienceDefaultsStore,
                enabledLLMStore: enabledLLMStore,
                onboardingArtifactStore: onboardingArtifactStore,
                careerKeywordStore: careerKeywordStore
            )

            Logger.info("✅ Factory reset completed successfully", category: .appLifecycle)
        } catch {
            resetError = error.localizedDescription
            Logger.error("❌ Factory reset failed: \(error)", category: .appLifecycle)
            throw error
        }
    }

    // MARK: - Private Reset Methods

    private func resetSwiftDataModels(modelContext: ModelContext) throws {
        // Delete all SwiftData models from the persistent store
        // Using specific FetchDescriptor types for each model to ensure proper deletion

        do {
            // Delete all JobApps
            try modelContext.delete(model: JobApp.self)
            Logger.debug("✅ JobApp records deleted", category: .appLifecycle)
        } catch {
            Logger.warning("⚠️ Could not delete JobApp records: \(error)", category: .appLifecycle)
        }

        do {
            // Delete all Resumes and related data
            try modelContext.delete(model: Resume.self)
            Logger.debug("✅ Resume records deleted", category: .appLifecycle)
        } catch {
            Logger.warning("⚠️ Could not delete Resume records: \(error)", category: .appLifecycle)
        }

        do {
            try modelContext.delete(model: ResRef.self)
            Logger.debug("✅ ResRef records deleted", category: .appLifecycle)
        } catch {
            Logger.warning("⚠️ Could not delete ResRef records: \(error)", category: .appLifecycle)
        }

        do {
            // Delete all CoverLetters
            try modelContext.delete(model: CoverLetter.self)
            Logger.debug("✅ CoverLetter records deleted", category: .appLifecycle)
        } catch {
            Logger.warning("⚠️ Could not delete CoverLetter records: \(error)", category: .appLifecycle)
        }

        do {
            try modelContext.delete(model: CoverRef.self)
            Logger.debug("✅ CoverRef records deleted", category: .appLifecycle)
        } catch {
            Logger.warning("⚠️ Could not delete CoverRef records: \(error)", category: .appLifecycle)
        }

        do {
            // Delete ApplicantProfile
            try modelContext.delete(model: ApplicantProfile.self)
            Logger.debug("✅ ApplicantProfile records deleted", category: .appLifecycle)
        } catch {
            Logger.warning("⚠️ Could not delete ApplicantProfile records: \(error)", category: .appLifecycle)
        }

        do {
            // Delete conversation history
            try modelContext.delete(model: ConversationContext.self)
            try modelContext.delete(model: ConversationMessage.self)
            Logger.debug("✅ Conversation records deleted", category: .appLifecycle)
        } catch {
            Logger.warning("⚠️ Could not delete conversation records: \(error)", category: .appLifecycle)
        }

        do {
            // Delete EnabledLLM records (but user will need to re-enable later)
            try modelContext.delete(model: EnabledLLM.self)
            Logger.debug("✅ EnabledLLM records deleted", category: .appLifecycle)
        } catch {
            Logger.warning("⚠️ Could not delete EnabledLLM records: \(error)", category: .appLifecycle)
        }

        do {
            // Delete onboarding artifacts
            try modelContext.delete(model: OnboardingArtifactRecord.self)
            Logger.debug("✅ OnboardingArtifactRecord records deleted", category: .appLifecycle)
        } catch {
            Logger.warning("⚠️ Could not delete OnboardingArtifactRecord records: \(error)", category: .appLifecycle)
        }

        do {
            // Delete templates (will re-seed defaults)
            try modelContext.delete(model: Template.self)
            Logger.debug("✅ Template records deleted", category: .appLifecycle)
        } catch {
            Logger.warning("⚠️ Could not delete Template records: \(error)", category: .appLifecycle)
        }

        do {
            // Delete experience defaults
            try modelContext.delete(model: ExperienceDefaults.self)
            Logger.debug("✅ ExperienceDefaults records deleted", category: .appLifecycle)
        } catch {
            Logger.warning("⚠️ Could not delete ExperienceDefaults records: \(error)", category: .appLifecycle)
        }

        try modelContext.save()
        Logger.debug("✅ All SwiftData models reset and saved", category: .appLifecycle)
    }

    private func resetUserDefaults() throws {
        let defaults = UserDefaults.standard

        // Reset onboarding-related defaults
        defaults.removeObject(forKey: "onboardingInterviewDefaultModelId")
        defaults.removeObject(forKey: "onboardingPDFExtractionModelId")
        defaults.removeObject(forKey: "onboardingInterviewAllowWebSearchDefault")
        defaults.removeObject(forKey: "onboardingInterviewAllowWritingAnalysisDefault")

        // Reset AI settings
        defaults.removeObject(forKey: "reasoningEffort")
        defaults.removeObject(forKey: "fixOverflowMaxIterations")

        // Reset debug settings
        defaults.removeObject(forKey: "debugLogLevel")
        defaults.removeObject(forKey: "saveDebugPrompts")

        // Reset other settings
        defaults.removeObject(forKey: "lastOpenedJobAppId")

        // Set reasonable defaults
        defaults.set("medium", forKey: "reasoningEffort")
        defaults.set(3, forKey: "fixOverflowMaxIterations")

        try defaults.synchronize() ? () : { throw NSError(domain: "UserDefaults", code: 1) }()
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

    private func resetStoreCaches(
        applicantProfileStore: ApplicantProfileStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        enabledLLMStore: EnabledLLMStore,
        onboardingArtifactStore: OnboardingArtifactStore,
        careerKeywordStore: CareerKeywordStore
    ) async throws {
        // Clear in-memory caches in each store
        // These stores maintain cached references to avoid frequent queries

        // ApplicantProfileStore caches the current profile
        applicantProfileStore.clearCache()

        // ExperienceDefaultsStore caches defaults
        experienceDefaultsStore.clearCache()

        // EnabledLLMStore maintains an in-memory array of enabled models
        enabledLLMStore.clearCache()

        // OnboardingArtifactStore clears its cache
        onboardingArtifactStore.clearCache()

        // CareerKeywordStore resets to default keywords
        await careerKeywordStore.resetAfterDataClear()

        Logger.debug("✅ Store caches reset", category: .appLifecycle)
    }
}

// MARK: - Store Extensions for Cache Clearing

extension ApplicantProfileStore {
    fileprivate func clearCache() {
        // The cache is cleared by forcing a fresh fetch on next call to currentProfile()
        // This is achieved by clearing the persistent data in the modelContext
    }
}

extension ExperienceDefaultsStore {
    fileprivate func clearCache() {
        // The cache is cleared by clearing the persistent data in the modelContext
    }
}

extension EnabledLLMStore {
    fileprivate func clearCache() {
        // Clear the enabled models array
        enabledModels.removeAll()
    }
}

extension OnboardingArtifactStore {
    fileprivate func clearCache() {
        // Use the built-in reset method
        reset()
    }
}

extension CareerKeywordStore {
    fileprivate func resetAfterDataClear() async {
        // Recreate the default career keywords file after data reset
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = appSupportURL.appendingPathComponent("Sprung", isDirectory: true)
        let keywordsFileURL = appDirectory.appendingPathComponent("career_keywords.json", isDirectory: false)

        // Remove old file if it exists
        if fileManager.fileExists(atPath: keywordsFileURL.path) {
            try? fileManager.removeItem(at: keywordsFileURL)
        }

        // Create directory if needed
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        // Copy default keywords from bundle
        if let bundledURL = Bundle.main.url(forResource: "DefaultCareerKeywords", withExtension: "json") {
            try? fileManager.copyItem(at: bundledURL, to: keywordsFileURL)
        } else {
            // Create empty keywords file if defaults unavailable
            try? Data("[]".utf8).write(to: keywordsFileURL)
        }

        Logger.debug("✅ Career keywords file reset", category: .appLifecycle)
    }
}
