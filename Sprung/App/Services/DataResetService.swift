//
//  DataResetService.swift
//  Sprung
//
//  Service responsible for coordinating a complete data reset across all stores and persistent layers.
//
import Foundation
@Observable
@MainActor
final class DataResetService {
    // MARK: - Properties
    var isResetting: Bool = false
    var resetError: String?
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

        // Reset debug settings
        defaults.removeObject(forKey: "debugLogLevel")
        defaults.removeObject(forKey: "saveDebugPrompts")
        defaults.removeObject(forKey: "showOnboardingDebugButton")
        defaults.removeObject(forKey: "forceQueryUserExperienceTool")

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
