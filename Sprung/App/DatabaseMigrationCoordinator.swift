//
//  DatabaseMigrationCoordinator.swift
//  Sprung
//
import Foundation
import SwiftData
@MainActor
final class DatabaseMigrationCoordinator {
    private let appState: AppState
    private let openRouterService: OpenRouterService
    private let enabledLLMStore: EnabledLLMStore
    private let modelValidationService: ModelValidationService
    init(
        appState: AppState,
        openRouterService: OpenRouterService,
        enabledLLMStore: EnabledLLMStore,
        modelValidationService: ModelValidationService
    ) {
        self.appState = appState
        self.openRouterService = openRouterService
        self.enabledLLMStore = enabledLLMStore
        self.modelValidationService = modelValidationService
    }
    func performStartupMigrations() {
        migrateSelectedModelsFromUserDefaults()
        migrateReasoningCapabilities()
        migrateDocAnalysisModelKeysV1()
        migrateAnthropicProviderKeysV1()
        scheduleModelValidation()
    }
    private func migrateSelectedModelsFromUserDefaults() {
        let data = UserDefaults.standard.data(forKey: "selectedOpenRouterModels") ?? Data()
        guard !data.isEmpty else { return }
        do {
            let oldSelectedModels = try JSONDecoder().decode(Set<String>.self, from: data)
            Logger.debug("🔄 Migrating \(oldSelectedModels.count) models from UserDefaults to EnabledLLM", category: .migration)
            for modelId in oldSelectedModels {
                if let openRouterModel = openRouterService.findModel(id: modelId) {
                    enabledLLMStore.updateModelCapabilities(from: openRouterModel)
                } else {
                    _ = enabledLLMStore.getOrCreateModel(id: modelId, displayName: modelId)
                }
            }
            UserDefaults.standard.removeObject(forKey: "selectedOpenRouterModels")
            Logger.debug("✅ Migration completed, UserDefaults cleared", category: .migration)
        } catch {
            Logger.error("❌ Failed to migrate from UserDefaults: \(error)", category: .migration)
        }
    }
    private func migrateReasoningCapabilities() {
        let allEnabledModels = try? enabledLLMStore.modelContext.fetch(FetchDescriptor<EnabledLLM>())
        guard let models = allEnabledModels, !models.isEmpty else { return }
        let migrationKey = "enabledLLMReasoningMigrationCompleted_v2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            Logger.debug("🔄 Reasoning capabilities migration already completed", category: .migration)
            return
        }
        var migrationCount = 0
        Logger.debug("🔄 Starting reasoning capabilities migration for \(models.count) models...", category: .migration)
        for enabledModel in models {
            if let openRouterModel = openRouterService.findModel(id: enabledModel.modelId) {
                let oldSupportsReasoning = enabledModel.supportsReasoning
                enabledModel.supportsReasoning = openRouterModel.supportsReasoning
                enabledModel.supportsImages = openRouterModel.supportsImages
                enabledModel.isTextToText = openRouterModel.isTextToText
                enabledModel.supportsStructuredOutput = openRouterModel.supportsStructuredOutput
                if oldSupportsReasoning != enabledModel.supportsReasoning {
                    migrationCount += 1
                    Logger.debug("📊 Updated \(enabledModel.modelId): reasoning \(oldSupportsReasoning) → \(enabledModel.supportsReasoning)", category: .migration)
                }
            } else {
                Logger.debug("⚠️ Could not find OpenRouter model for \(enabledModel.modelId) during migration", category: .migration)
            }
        }
        do {
            try enabledLLMStore.modelContext.save()
            enabledLLMStore.refreshEnabledModels()
            UserDefaults.standard.set(true, forKey: migrationKey)
            Logger.debug("✅ Reasoning capabilities migration completed: \(migrationCount) models updated", category: .migration)
        } catch {
            Logger.error("❌ Failed to save reasoning capabilities migration: \(error)", category: .migration)
        }
    }
    /// Removes the four legacy per-pass document model keys replaced by the
    /// single Anthropic document-analysis model ("onboardingDocAnalysisModelId"),
    /// plus the dead OpenAI-era interview key (the interview reads
    /// "onboardingAnthropicModelId"; the old key may hold a stale gpt-* value).
    private func migrateDocAnalysisModelKeysV1() {
        let migrationKey = "docAnalysisModelKeysMigrationCompleted_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        let legacyKeys = [
            "onboardingPDFExtractionModelId",
            "onboardingDocSummaryModelId",
            "skillBankModelId",
            "kcExtractionModelId",
            "onboardingInterviewDefaultModelId"
        ]
        for key in legacyKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
        Logger.debug("✅ docAnalysisModelKeysMigrationV1: removed \(legacyKeys.count) legacy document model keys", category: .migration)
    }

    /// Git ingest and card merge moved from OpenRouter to Anthropic (Wave 3).
    /// Stored OpenRouter-format ids ("anthropic/claude-…") are invalid against the
    /// Anthropic API — clear them so the pickers surface instead of 404ing.
    private func migrateAnthropicProviderKeysV1() {
        let migrationKey = "anthropicProviderKeysMigrationCompleted_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        for key in ["onboardingGitIngestModelId", "onboardingCardMergeModelId"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
        Logger.debug("✅ anthropicProviderKeysMigrationV1: cleared git/merge model keys for provider move", category: .migration)
    }
    private func scheduleModelValidation() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await self?.validateEnabledModels()
        }
    }
    @MainActor
    private func validateEnabledModels() async {
        guard appState.hasValidOpenRouterKey else {
            Logger.debug("⚠️ Skipping model validation: missing OpenRouter key")
            return
        }
        let enabledModelIds = enabledLLMStore.enabledModelIds
        guard !enabledModelIds.isEmpty else {
            Logger.debug("ℹ️ No enabled models to validate")
            return
        }
        Logger.debug("🔍 Validating \(enabledModelIds.count) enabled models...")
        let validationResults = await modelValidationService.validateModels(enabledModelIds)
        for (modelId, result) in validationResults {
            if result.isAvailable {
                if let capabilities = result.actualCapabilities {
                    enabledLLMStore.updateModelCapabilities(
                        modelId: modelId,
                        supportsJSONSchema: capabilities.supportsStructuredOutputs || capabilities.supportsResponseFormat,
                        supportsImages: capabilities.supportsImages,
                        supportsReasoning: capabilities.supportedParameters.contains { $0.lowercased().contains("reasoning") }
                    )
                    Logger.debug("✅ Model \(modelId) validated successfully")
                }
            } else {
                let message = result.error ?? "Unknown error"
                Logger.warning("❌ Model \(modelId) validation failed: \(message)")
            }
        }
        let failedCount = validationResults.values.filter { !$0.isAvailable }.count
        if failedCount > 0 {
            Logger.info("⚠️ \(failedCount) of \(enabledModelIds.count) enabled models failed validation")
        } else {
            Logger.info("✅ All \(enabledModelIds.count) enabled models validated successfully")
        }
    }
}
