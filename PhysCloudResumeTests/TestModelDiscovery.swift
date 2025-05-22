// TestModelDiscovery.swift
// PhysCloudResume
//
// Created to fix model compatibility issues in tests

import Foundation
@testable import PhysCloudResume

/// This class provides dynamic model discovery for tests to use available models from each provider
class TestModelDiscovery {
    
    /// Available model substitutions for each provider
    struct ModelSubstitution {
        let preferredModel: String
        let alternatives: [String]
        let provider: String
        
        init(preferredModel: String, alternatives: [String], provider: String) {
            self.preferredModel = preferredModel
            self.alternatives = alternatives
            self.provider = provider
        }
    }
    
    /// Model substitutions for each provider - UPDATED with only required models
    static let modelSubstitutions: [ModelSubstitution] = [
        // OpenAI models - using only gpt-4.1, o3, o4-mini
        ModelSubstitution(
            preferredModel: "gpt-4.1", 
            alternatives: ["gpt-4.1"], 
            provider: AIModels.Provider.openai
        ),
        ModelSubstitution(
            preferredModel: "o4-mini", 
            alternatives: ["o4-mini"],
            provider: AIModels.Provider.openai
        ),
        ModelSubstitution(
            preferredModel: "o3",
            alternatives: ["o3"],
            provider: AIModels.Provider.openai
        ),

        // Grok models - using only grok-3-mini-fast, grok-3
        ModelSubstitution(
            preferredModel: "grok-3-mini-fast", 
            alternatives: ["grok-3-mini-fast"],
            provider: AIModels.Provider.grok
        ),
        ModelSubstitution(
            preferredModel: "grok-3", 
            alternatives: ["grok-3"],
            provider: AIModels.Provider.grok
        ),
        
        // Gemini models - using only gemini-2.0-flash
        ModelSubstitution(
            preferredModel: "gemini-2.0-flash", 
            alternatives: ["gemini-2.0-flash"],
            provider: AIModels.Provider.gemini
        ),
        
        // Claude models - using only claude-3-5-haiku-latest
        ModelSubstitution(
            preferredModel: "claude-3-5-haiku-latest",
            alternatives: ["claude-3-5-haiku-latest"],
            provider: AIModels.Provider.claude
        )
    ]
    
    // MARK: – Ensure we have one model per provider type
    static func ensureOneModelPerProvider(models: [String]) -> [String] {
        var providerModels: [String: String] = [:]
        
        // Find best available model for each provider
        for model in models {
            let provider = AIModels.providerForModel(model)
            if providerModels[provider] == nil {
                providerModels[provider] = model
            }
        }
        
        // Return list of chosen models
        return Array(providerModels.values)
    }
    
    /// Gets test models to use based on the specified list of models
    /// - Parameter modelService: The model service (not used in this updated version)
    /// - Returns: Array of models to use in tests
    static func getTestModels(modelService: ModelService) -> [String] {
        // Use the specific models requested for testing
        let testModels = [
            "gpt-4.1",       // OpenAI
            "o3",            // OpenAI
            "o4-mini",       // OpenAI
            "claude-3.5-haiku", // Claude
            "grok-3-mini-fast",  // Grok
            "grok-3",        // Grok
            "gemini-2.0-flash"   // Gemini
        ]
        
        // Log the test models for debugging
        Logger.debug("⚡ Using specific test models: \(testModels.joined(separator: ", "))")
        
        return testModels
    }
    
    /// Creates an expectations dictionary for test validation
    /// - Parameter testModels: Array of models being tested
    /// - Returns: Dictionary mapping model names to expected success (true/false)
    static func createExpectedResults(for testModels: [String]) -> [String: Bool] {
        // By default, all models are expected to succeed except mini models
        var expectations: [String: Bool] = [:]
        
        for model in testModels {
            let modelLower = model.lowercased()
            let isMiniModel = modelLower.contains("mini") || modelLower.contains("-mini")
            
            // Set expectations based on model type
            if isMiniModel && (modelLower.contains("o4") || modelLower.contains("gpt-4o")) {
                // o4-mini and similar are expected to fail with reasoning_effort error
                expectations[model] = false
            } else {
                // All other models should succeed
                expectations[model] = true
            }
        }
        
        return expectations
    }
}
