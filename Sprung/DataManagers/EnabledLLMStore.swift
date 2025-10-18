//
//  EnabledLLMStore.swift
//  Sprung
//
//  Store for managing enabled LLM models with SwiftData persistence
//

import Foundation
import SwiftData
import Combine

/// Store for managing enabled LLM models
@MainActor
@Observable
class EnabledLLMStore: SwiftDataStore {
    var enabledModels: [EnabledLLM] = []
    unowned let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadEnabledModels()
    }
    
    private func loadEnabledModels() {
        do {
            let descriptor = FetchDescriptor<EnabledLLM>(
                predicate: #Predicate<EnabledLLM> { $0.isEnabled },
                sortBy: [SortDescriptor(\.lastUsed, order: .reverse)]
            )
            enabledModels = try modelContext.fetch(descriptor)
        } catch {
            Logger.error("Failed to load enabled models: \(error)")
            enabledModels = []
        }
    }
    
    /// Get or create an EnabledLLM for the given model ID
    func getOrCreateModel(id: String, displayName: String, provider: String = "") -> EnabledLLM {
        if let existing = enabledModels.first(where: { $0.modelId == id }) {
            return existing
        }
        
        let newModel = EnabledLLM(modelId: id, displayName: displayName, provider: provider)
        enabledModels.append(newModel)
        
        modelContext.insert(newModel)
        try? modelContext.save()
        
        return newModel
    }
    
    /// Update model capabilities from OpenRouter model info
    func updateModelCapabilities(from openRouterModel: OpenRouterModel) {
        let enabledModel = getOrCreateModel(
            id: openRouterModel.id,
            displayName: openRouterModel.name,
            provider: openRouterModel.providerName
        )
        
        // Update capabilities from OpenRouter metadata
        enabledModel.supportsImages = openRouterModel.supportsImages
        enabledModel.supportsReasoning = openRouterModel.supportsReasoning
        enabledModel.isTextToText = openRouterModel.isTextToText
        enabledModel.contextLength = openRouterModel.contextLength ?? 0
        enabledModel.pricingTier = openRouterModel.costLevelDescription()
        
        // Initially assume structured output support, will be verified on first use
        enabledModel.supportsStructuredOutput = openRouterModel.supportsStructuredOutput
        enabledModel.supportsJSONSchema = openRouterModel.supportsStructuredOutput
        
        // Ensure model is enabled when capabilities are updated
        enabledModel.isEnabled = true
        
        try? modelContext.save()
        
        // Refresh in-memory state to reflect database changes
        refreshEnabledModels()
    }
    
    /// Record that a model failed with JSON schema
    func recordJSONSchemaFailure(modelId: String, reason: String) {
        if let model = enabledModels.first(where: { $0.modelId == modelId }) {
            model.recordJSONSchemaFailure(reason: reason)
            try? modelContext.save()
        }
    }
    
    /// Record that a model succeeded with JSON schema
    func recordJSONSchemaSuccess(modelId: String) {
        if let model = enabledModels.first(where: { $0.modelId == modelId }) {
            model.recordJSONSchemaSuccess()
            try? modelContext.save()
        }
    }
    
    /// Check if model should avoid JSON schema
    func shouldAvoidJSONSchema(modelId: String) -> Bool {
        return enabledModels.first(where: { $0.modelId == modelId })?.shouldAvoidJSONSchema ?? false
    }
    
    /// Update model capabilities from validation results
    func updateModelCapabilities(
        modelId: String,
        supportsJSONSchema: Bool? = nil,
        supportsImages: Bool? = nil,
        supportsReasoning: Bool? = nil,
        isTextToText: Bool? = nil
    ) {
        guard let model = enabledModels.first(where: { $0.modelId == modelId }) else {
            return
        }
        
        if let supportsJSONSchema {
            model.supportsJSONSchema = supportsJSONSchema
            model.supportsStructuredOutput = supportsJSONSchema
        }
        if let supportsImages {
            model.supportsImages = supportsImages
        }
        if let supportsReasoning {
            model.supportsReasoning = supportsReasoning
        }
        if let isTextToText {
            model.isTextToText = isTextToText
        }
        
        model.lastUsed = Date()
        try? modelContext.save()
        refreshEnabledModels()
        let schemaDescription = supportsJSONSchema.map { "\($0)" } ?? "<unchanged>"
        let imagesDescription = supportsImages.map { "\($0)" } ?? "<unchanged>"
        Logger.debug("📊 Updated capabilities for \(modelId): JSON Schema=\(schemaDescription), Images=\(imagesDescription)")
    }
    
    /// Disable a model by ID
    func disableModel(id: String) {
        // Update database record
        let enabledModel = getOrCreateModel(id: id, displayName: id)
        enabledModel.isEnabled = false
        
        try? modelContext.save()
        
        // Refresh in-memory state to reflect database changes
        refreshEnabledModels()
    }
    
    /// Refresh the in-memory enabled models array from the database
    func refreshEnabledModels() {
        do {
            let descriptor = FetchDescriptor<EnabledLLM>(
                predicate: #Predicate<EnabledLLM> { $0.isEnabled },
                sortBy: [SortDescriptor(\.lastUsed, order: .reverse)]
            )
            enabledModels = try modelContext.fetch(descriptor)
            Logger.debug("🔄 Refreshed EnabledLLMStore: \(enabledModels.count) enabled models")
        } catch {
            Logger.error("❌ Failed to refresh enabled models: \\(error)")
        }
    }
    
    /// Get all enabled model IDs
    var enabledModelIds: [String] {
        return enabledModels.map(\.modelId)
    }
    
    /// Returns true if the provided model ID is marked as enabled
    func isModelEnabled(_ modelId: String) -> Bool {
        guard let model = enabledModels.first(where: { $0.modelId == modelId }) else {
            return true
        }
        return model.isEnabled
    }
}
