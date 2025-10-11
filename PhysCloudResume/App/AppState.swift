//
//  AppState.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

import Observation
import SwiftUI
import SwiftData

@Observable
@MainActor
class AppState {
    init(openRouterService: OpenRouterService, modelValidationService: ModelValidationService) {
        self.openRouterService = openRouterService
        self.modelValidationService = modelValidationService
        configureOpenRouterService()
    }
    var isReadOnlyMode = false
    
    // OpenRouter service
    let openRouterService: OpenRouterService
    
    // EnabledLLM store for persistent model management
    var enabledLLMStore: EnabledLLMStore?
    let modelValidationService: ModelValidationService

    // Debug/diagnostics settings
    var debugSettingsStore: DebugSettingsStore?

    
    /// Initialize the EnabledLLM store with a ModelContext
    func initializeWithModelContext(_ modelContext: ModelContext, enabledLLMStore: EnabledLLMStore) {
        self.enabledLLMStore = enabledLLMStore
        
        // Migrate from UserDefaults if this is the first time
        migrateFromUserDefaults()
        
        // Migrate reasoning capabilities for existing models
        migrateReasoningCapabilities()
        
        // Start model validation in background after a delay to not block app launch
        Task {
            // Wait 3 seconds after app launch to start validation
            try? await Task.sleep(for: .seconds(3))
            await validateEnabledModels()
        }
    }
    
    /// Migrate from old UserDefaults-based storage to EnabledLLM
    private func migrateFromUserDefaults() {
        guard let store = enabledLLMStore else { return }
        
        // Check if we have old UserDefaults data to migrate
        let data = UserDefaults.standard.data(forKey: "selectedOpenRouterModels") ?? Data()
        guard !data.isEmpty else { return }
        
        do {
            let oldSelectedModels = try JSONDecoder().decode(Set<String>.self, from: data)
            Logger.debug("🔄 Migrating \(oldSelectedModels.count) models from UserDefaults to EnabledLLM", category: .migration)
            
            // Create EnabledLLM entries for each model
            for modelId in oldSelectedModels {
                if let openRouterModel = openRouterService.findModel(id: modelId) {
                    store.updateModelCapabilities(from: openRouterModel)
                } else {
                    // Create basic entry for models we can't find
                    let _ = store.getOrCreateModel(id: modelId, displayName: modelId)
                }
            }
            
            // Clear the old UserDefaults data
            UserDefaults.standard.removeObject(forKey: "selectedOpenRouterModels")
            Logger.debug("✅ Migration completed, UserDefaults cleared")
            
        } catch {
            Logger.error("❌ Failed to migrate from UserDefaults: \(error)", category: .migration)
        }
    }
    
    /// Migrate reasoning capabilities for existing EnabledLLM records
    /// This ensures existing models get the new supportsReasoning property set correctly
    private func migrateReasoningCapabilities() {
        guard let store = enabledLLMStore else { return }
        
        // Check if migration is needed by looking for any models without reasoning capability set
        let allEnabledModels = try? store.modelContext.fetch(FetchDescriptor<EnabledLLM>())
        guard let models = allEnabledModels, !models.isEmpty else { return }
        
        // Use a versioned flag to check if migration has been performed (v2 includes thinking models)
        let migrationKey = "enabledLLMReasoningMigrationCompleted_v2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
        Logger.debug("🔄 Reasoning capabilities migration already completed", category: .migration)
            return
        }
        
        var migrationCount = 0
        
        Logger.debug("🔄 Starting reasoning capabilities migration for \(models.count) models...", category: .migration)
        
        for enabledModel in models {
            // Find the corresponding OpenRouter model
            if let openRouterModel = openRouterService.findModel(id: enabledModel.modelId) {
                let oldSupportsReasoning = enabledModel.supportsReasoning
                enabledModel.supportsReasoning = openRouterModel.supportsReasoning
                
                // Also update other capabilities that might have changed
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
        
        // Save changes
        do {
            try store.modelContext.save()
            store.refreshEnabledModels()
            
            // Mark migration as completed
            UserDefaults.standard.set(true, forKey: migrationKey)
            
            Logger.debug("✅ Reasoning capabilities migration completed: \(migrationCount) models updated", category: .migration)
        } catch {
            Logger.error("❌ Failed to save reasoning capabilities migration: \(error)", category: .migration)
        }
    }
    
    private func configureOpenRouterService() {
        // Ensure migration from UserDefaults to Keychain (one-time, idempotent)
        APIKeyManager.migrateFromUserDefaults()
        let openRouterApiKey = APIKeyManager.get(.openRouter) ?? ""
        if !openRouterApiKey.isEmpty {
            openRouterService.configure(apiKey: openRouterApiKey)
        }
    }
    
    func reconfigureOpenRouterService(using llmService: LLMService) {
        configureOpenRouterService()
        // Also reconfigure LLMService to use the updated API key
        llmService.reconfigureClient()
    }
    
    /// Validate all enabled models at startup to check availability and capabilities
    private func validateEnabledModels() async {
        guard let store = enabledLLMStore, hasValidOpenRouterKey else {
            Logger.debug("⚠️ Skipping model validation: no EnabledLLM store or API key")
            return
        }
        
        let enabledModelIds = store.enabledModelIds
        guard !enabledModelIds.isEmpty else {
            Logger.debug("ℹ️ No enabled models to validate")
            return
        }
        
        Logger.debug("🔍 Validating \(enabledModelIds.count) enabled models...")
        
        // Use ModelValidationService to check each model
        let validationResults = await modelValidationService.validateModels(enabledModelIds)
        
        // Update capabilities based on validation results
        for (modelId, result) in validationResults {
            if result.isAvailable {
                // Update the EnabledLLM with actual capabilities
                if let capabilities = result.actualCapabilities {
                    store.updateModelCapabilities(
                        modelId: modelId,
                        supportsJSONSchema: capabilities.supportsStructuredOutputs || capabilities.supportsResponseFormat,
                        supportsImages: capabilities.supportsImages,
                        supportsReasoning: capabilities.supportedParameters.contains { $0.lowercased().contains("reasoning") }
                    )
                    Logger.debug("✅ Model \(modelId) validated successfully")
                }
            } else {
                // Mark model as having issues but don't disable it automatically
                // Let the user decide what to do with failed models
                Logger.warning("❌ Model \(modelId) validation failed: \(result.error ?? "Unknown error")")
            }
        }
        
        // Show user notification if any models failed validation
        let failedCount = validationResults.values.filter { !$0.isAvailable }.count
        if failedCount > 0 {
            Logger.info("⚠️ \(failedCount) of \(enabledModelIds.count) enabled models failed validation")
            // Note: In a real app, you might want to show a notification banner here
        } else {
            Logger.info("✅ All \(enabledModelIds.count) enabled models validated successfully")
        }
    }
}
