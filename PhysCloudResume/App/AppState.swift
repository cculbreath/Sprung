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
    // Singleton instance
    static let shared = AppState()
    
    // Private initializer to prevent external instantiation
    private init() {
        configureOpenRouterService()
        restoreSelectedTab()
    }
    var showNewAppSheet: Bool = false
    var showSlidingList: Bool = false
    var selectedTab: TabList = .listing {
        didSet {
            // Save to UserDefaults when changed
            UserDefaults.standard.set(selectedTab.rawValue, forKey: "selectedTab")
        }
    }
    var dragInfo = DragInfo()

    // AI job recommendation properties
    var recommendedJobId: UUID?
    var isLoadingRecommendation: Bool = false
    
    // Import job apps sheet (disabled - functionality removed)
    // var showImportJobAppsSheet: Bool = false
    
    // Selected job app and resume for template editor
    var selectedJobApp: JobApp?
    var selectedResume: Resume? {
        selectedJobApp?.selectedRes
    }
    
    // Persistent selected job app UUID
    @ObservationIgnored @AppStorage("selectedJobAppId") private var selectedJobAppId: String = ""
    
    // OpenRouter service
    let openRouterService = OpenRouterService.shared
    
    // EnabledLLM store for persistent model management
    var enabledLLMStore: EnabledLLMStore?
    
    // Model validation service
    let modelValidationService = ModelValidationService.shared
    
    // Resume revision view model
    var resumeReviseViewModel: ResumeReviseViewModel?
    
    // Global reasoning stream manager for AI thinking display
    var globalReasoningStreamManager = ReasoningStreamManager()
    
    
    /// Restore the selected tab from UserDefaults
    private func restoreSelectedTab() {
        if let savedTabRawValue = UserDefaults.standard.object(forKey: "selectedTab") as? String,
           let savedTab = TabList(rawValue: savedTabRawValue) {
            selectedTab = savedTab
            Logger.debug("✅ Restored selected tab: \(savedTab.rawValue)")
        }
    }
    
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
            Logger.debug("🔄 Migrating \(oldSelectedModels.count) models from UserDefaults to EnabledLLM")
            
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
            Logger.error("❌ Failed to migrate from UserDefaults: \(error)")
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
            Logger.debug("🔄 Reasoning capabilities migration already completed")
            return
        }
        
        var migrationCount = 0
        
        Logger.debug("🔄 Starting reasoning capabilities migration for \(models.count) models...")
        
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
                    Logger.debug("📊 Updated \(enabledModel.modelId): reasoning \(oldSupportsReasoning) → \(enabledModel.supportsReasoning)")
                }
            } else {
                Logger.debug("⚠️ Could not find OpenRouter model for \(enabledModel.modelId) during migration")
            }
        }
        
        // Save changes
        do {
            try store.modelContext.save()
            store.refreshEnabledModels()
            
            // Mark migration as completed
            UserDefaults.standard.set(true, forKey: migrationKey)
            
            Logger.debug("✅ Reasoning capabilities migration completed: \(migrationCount) models updated")
        } catch {
            Logger.error("❌ Failed to save reasoning capabilities migration: \(error)")
        }
    }
    
    private func configureOpenRouterService() {
        let openRouterApiKey = UserDefaults.standard.string(forKey: "openRouterApiKey") ?? ""
        if !openRouterApiKey.isEmpty {
            openRouterService.configure(apiKey: openRouterApiKey)
        }
    }
    
    func reconfigureOpenRouterService() {
        configureOpenRouterService()
        // Also reconfigure LLMService to use the updated API key
        LLMService.shared.reconfigureClient()
    }
    
    /// Save the selected job app ID for persistence
    func saveSelectedJobApp(_ jobApp: JobApp?) {
        if let jobApp = jobApp {
            selectedJobAppId = jobApp.id.uuidString
        } else {
            selectedJobAppId = ""
        }
    }
    
    /// Restore the selected job app from persistence
    func restoreSelectedJobApp(from jobAppStore: JobAppStore) {
        guard !selectedJobAppId.isEmpty,
              let uuid = UUID(uuidString: selectedJobAppId) else {
            return
        }
        
        // Find the job app with the saved ID
        if let jobApp = jobAppStore.jobApps.first(where: { $0.id == uuid }) {
            jobAppStore.selectedApp = jobApp
            selectedJobApp = jobApp
            Logger.debug("✅ Restored selected job app: \(jobApp.jobPosition)")
        } else {
            // Clear invalid ID if job app no longer exists
            selectedJobAppId = ""
            Logger.debug("⚠️ Could not restore job app with ID: \(selectedJobAppId)")
        }
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
                        supportsImages: capabilities.supportsImages
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
