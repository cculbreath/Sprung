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
    private let defaultModelSeeds: [(id: String, displayName: String, provider: String)] = [
        ("anthropic/haiku-4.5", "Anthropic Claude Haiku 4.5", "Anthropic"),
        ("anthropic/claude-opus-4.1", "Anthropic Claude Opus 4.1", "Anthropic"),
        ("anthropic/claude-sonnet-4.5", "Anthropic Claude Sonnet 4.5", "Anthropic"),
        ("deepseek/deepseek-v3.1-terminus", "DeepSeek Terminus v3.1", "DeepSeek"),
        ("deepseek/deepseek-v3.2-exp", "DeepSeek v3.2 Experimental", "DeepSeek"),
        ("google/gemini-2.0-flash-001", "Gemini 2.0 Flash", "Google"),
        ("google/gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite", "Google"),
        ("google/gemini-2.5-pro", "Gemini 2.5 Pro", "Google"),
        ("openai/gpt-4.1", "GPT-4.1", "OpenAI"),
        ("openai/gpt-5.1", "GPT-5.1", "OpenAI"),
        ("openai/gpt-5", "GPT-5", "OpenAI"),
        ("openai/gpt-5-chat", "GPT-5 Chat", "OpenAI"),
        ("openai/gpt-5-pro", "GPT-5 Pro", "OpenAI"),
        ("openai/o3", "OpenAI o3", "OpenAI"),
        ("x-ai/grok-4", "Grok 4", "xAI"),
        ("x-ai/grok-4-fast", "Grok 4 Fast", "xAI")
    ]
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadEnabledModels()
        seedDefaultModelsIfNeeded()
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

    func clearCache() {
        enabledModels.removeAll()
    }

    private func seedDefaultModelsIfNeeded() {
        guard enabledModels.isEmpty else { return }

        let now = Date()
        for seed in defaultModelSeeds {
            let record = getOrCreateModel(id: seed.id, displayName: seed.displayName, provider: seed.provider)
            record.isEnabled = true
            record.dateAdded = now
            record.lastUsed = now
        }
        try? modelContext.save()
        refreshEnabledModels()
    }
}
