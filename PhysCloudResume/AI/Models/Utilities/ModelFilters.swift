//
//  ModelFilters.swift
//  PhysCloudResume
//
//  Created by Claude on 5/20/25.
//

import Foundation
import SwiftUI

/// Provides filtering and validation for various model operations
class ModelFilters {
    
    // MARK: - API Key Validation
    
    /// Validates an API key for a given provider
    /// - Parameters:
    ///   - apiKey: The API key to validate
    ///   - provider: The provider identifier
    /// - Returns: A cleaned and validated API key, or nil if invalid
    static func validateAPIKey(_ apiKey: String, for provider: String) -> String? {
        // Clean the key first to remove any whitespace
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it's empty or "none"
        guard !cleanKey.isEmpty && cleanKey != "none" else {
            Logger.debug("⚠️ API key for \(provider) is empty or 'none'")
            return nil
        }
        
        // Check format based on provider
        switch provider {
        case AIModels.Provider.openai:
            if (!cleanKey.hasPrefix("sk-") && !cleanKey.hasPrefix("sk-proj-")) || cleanKey.count < 40 {
                Logger.debug("⚠️ OpenAI API key has invalid format (should start with 'sk-' or 'sk-proj-' and be at least 40 chars)")
                return nil
            }
            
        case AIModels.Provider.claude:
            if !cleanKey.hasPrefix("sk-ant-") || cleanKey.count < 60 {
                Logger.debug("⚠️ Claude API key has invalid format (should start with 'sk-ant-' and be at least 60 chars)")
                return nil
            }
            
        case AIModels.Provider.grok:
            if (!cleanKey.hasPrefix("gsk_") && !cleanKey.hasPrefix("xai-")) || cleanKey.count < 30 {
                Logger.debug("⚠️ Grok API key has invalid format (should start with 'gsk_' or 'xai-' and be at least 30 chars)")
                return nil
            }
            
        case AIModels.Provider.gemini:
            if !cleanKey.hasPrefix("AIza") || cleanKey.count < 20 {
                Logger.debug("⚠️ Gemini API key has invalid format (should start with 'AIza' and be at least 20 chars)")
                return nil
            }
            
        default:
            if cleanKey.count < 20 {
                Logger.debug("⚠️ API key for \(provider) is too short (length < 20)")
                return nil
            }
        }
        
        // Log successful validation (without revealing the key)
        let firstChars = String(cleanKey.prefix(4))
        let length = cleanKey.count
        Logger.debug("✅ Valid API key format for \(provider): First chars: \(firstChars), Length: \(length)")
        
        return cleanKey
    }
    
    // MARK: - API Key Status for UI
    
    /// Status of an API key for UI display
    enum KeyStatus {
        case valid    // Key is present and has correct format
        case invalid  // Key is present but has incorrect format
        case missing  // Key is not provided
        
        /// Color to use for the status indicator
        var color: Color {
            switch self {
            case .valid: 
                return .green
            case .invalid: 
                return .orange
            case .missing: 
                return .red
            }
        }
        
        /// Text to display for the status
        var text: String {
            switch self {
            case .valid:
                return "Valid"
            case .invalid:
                return "Invalid format"
            case .missing:
                return "Not configured"
            }
        }
    }
    
    /// Gets the visual status for an API key to display in UI
    /// - Parameters:
    ///   - provider: The provider name
    ///   - apiKey: The API key to check
    /// - Returns: The key status (valid, invalid, missing)
    static func visualKeyStatus(provider: String, apiKey: String) -> KeyStatus {
        // First check if the key is empty or "none"
        if apiKey.isEmpty || apiKey == "none" {
            return .missing
        }
        
        // Check format based on provider requirements
        switch provider {
        case AIModels.Provider.openai:
            // OpenAI keys typically start with "sk-" or "sk-proj-" and are about 50-150 chars
            if (apiKey.hasPrefix("sk-") || apiKey.hasPrefix("sk-proj-")) && apiKey.count >= 40 {
                return .valid
            }
            
        case AIModels.Provider.claude:
            // Claude keys typically start with "sk-ant-" and are about 80 chars
            if apiKey.hasPrefix("sk-ant-") && apiKey.count >= 60 {
                return .valid
            }
            
        case AIModels.Provider.grok:
            // Grok keys either start with "gsk_" (Groq) or "xai-" (X.AI)
            if (apiKey.hasPrefix("gsk_") || apiKey.hasPrefix("xai-")) && apiKey.count >= 30 {
                return .valid
            }
            
        case AIModels.Provider.gemini:
            // Gemini keys typically start with "AIza" and are at least 30 chars
            if apiKey.hasPrefix("AIza") && apiKey.count >= 20 {
                return .valid
            }
            
        default:
            // For unknown providers, just check it's not too short
            if apiKey.count >= 20 {
                return .valid
            }
        }
        
        // If we got here, the key format is invalid
        return .invalid
    }
    
    /// Filters OpenAI models to include only those we want to show
    /// - Parameter models: The complete list of models from the API
    /// - Returns: A filtered list of models
    static func filterOpenAIModels(_ models: [String]) -> [String] {
        // Map of model priority - key models to always include if available
        let keyModels = [
            "gpt-4o": 100,
            "gpt-4": 90,
            "gpt-4-turbo": 85,
            "gpt-4.5-turbo": 95,
            "gpt-3.5-turbo": 80,
            "o1": 98,
            "o1-mini": 75,
            "o1-preview": 97,
            "o3": 96,
            "o4-mini": 94
        ]
        
        // First, create a map of model family to models
        var familyMap: [String: [String]] = [:]
        
        // First pass: identify all relevant model families
        for model in models {
            let id = model.lowercased()
            
            // Skip non-chat models and special-purpose models
            if id.contains("embedding") || id.contains("whisper") || 
               id.contains("tts-") || id.contains("dall-e") || 
               id.contains("text-moderation") || id.contains("babbage") ||
               id.contains("davinci") || id.contains("curie") || id.contains("ada") {
                continue
            }
            
            // Check if it's a GPT or Reasoning (o*) model
            let isGptModel = id.contains("gpt-") 
            let isReasoningModel = id.starts(with: "o1") || id.starts(with: "o3") || 
                                  id.starts(with: "o4") || id == "o1" || id == "o3"
            
            if !isGptModel && !isReasoningModel {
                continue
            }
            
            // Extract the model family (base name)
            let family = getBaseModelName(id)
            
            // Add to the family map
            if familyMap[family] == nil {
                familyMap[family] = []
            }
            familyMap[family]?.append(model)
        }
        
        Logger.debug("📋 Found \(familyMap.count) OpenAI model families")
        
        // Second pass: pick the best representative from each family
        var result: [String] = []
        
        for (family, familyModels) in familyMap {
            // Sort models by our custom priority rules
            let sortedModels = familyModels.sorted { model1, model2 in
                let id1 = model1.lowercased()
                let id2 = model2.lowercased()
                
                // Rule 1: Prefer exact base models
                if exactlyMatchesBaseModel(id1) && !exactlyMatchesBaseModel(id2) {
                    return true
                }
                if !exactlyMatchesBaseModel(id1) && exactlyMatchesBaseModel(id2) {
                    return false
                }
                
                // Rule 2: For dated models, prefer the latest one (reverse sort)
                if id1.contains("-20") && id2.contains("-20") {
                    return id1 > id2
                }
                
                // Rule 3: Prefer models without dates over dated ones (except for preview models)
                if !id1.contains("-20") && id2.contains("-20") && !id1.contains("preview") {
                    return true
                }
                if id1.contains("-20") && !id2.contains("-20") && !id2.contains("preview") {
                    return false
                }
                
                // Rule 4: Prefer shorter names over longer ones
                return id1.count < id2.count
            }
            
            // Add the best representative
            if let bestModel = sortedModels.first {
                result.append(bestModel)
            }
        }
        
        // Ensure we include all key models that exist in the original list
        for (keyModel, _) in keyModels.sorted(by: { $0.value > $1.value }) {
            if let exactMatch = models.first(where: { $0.lowercased() == keyModel.lowercased() }) {
                // Check if the model family is already represented
                let family = getBaseModelName(keyModel)
                let hasFamily = result.contains { getBaseModelName($0.lowercased()) == family }
                
                // If it's a key model, always include it
                if !result.contains(where: { $0.lowercased() == keyModel.lowercased() }) {
                    // For key models, either add them or replace the family representative
                    // with the exact key model
                    if hasFamily {
                        // Find and replace the family representative with our key model
                        if let index = result.firstIndex(where: { getBaseModelName($0.lowercased()) == family }) {
                            result[index] = exactMatch
                        }
                    } else {
                        result.append(exactMatch)
                    }
                }
            }
        }
        
        // If we somehow got nothing, fall back to a broad filter
        if result.isEmpty {
            Logger.debug("⚠️ No models matched our filters, returning raw list")
            return models.filter { model in
                let id = model.lowercased()
                return (id.contains("gpt-") || id.starts(with: "o")) &&
                       !id.contains("embedding") && !id.contains("whisper") && 
                       !id.contains("tts-") && !id.contains("dall-e")
            }
        }
        
        // Log how many models we kept
        Logger.debug("📋 Filtered \(models.count) OpenAI models down to \(result.count) models")
        
        return result.sorted()
    }
    
    /// Checks if a model ID exactly matches one of our defined base models
    /// - Parameter modelId: The model ID to check
    /// - Returns: True if it's an exact match for a base model
    private static func exactlyMatchesBaseModel(_ modelId: String) -> Bool {
        let baseModels = [
            "gpt-4", "gpt-4o", "gpt-3.5-turbo", "gpt-4-turbo", "gpt-4.5-turbo",
            "o1", "o1-mini", "o1-preview", "o3", "o4-mini"
        ]
        return baseModels.contains(modelId.lowercased())
    }
    
    /// Determines if a model name is a "base" model without version suffixes
    /// - Parameter modelName: The model name to check
    /// - Returns: True if this is a base model
    private static func isBaseModel(_ modelName: String) -> Bool {
        let baseModels = ["gpt-4", "gpt-4o", "gpt-3.5-turbo", "o1", "o3", "o4-mini"]
        return baseModels.contains(modelName.lowercased())
    }
    
    /// Extracts the base name of a model (e.g., "gpt-4o-2024-05-13" -> "gpt-4o")
    /// - Parameter modelName: The full model name
    /// - Returns: The base model name
    private static func getBaseModelName(_ modelName: String) -> String {
        let lowercased = modelName.lowercased()
        
        // Handle special cases first
        if lowercased.starts(with: "gpt-4.5-preview") {
            return "gpt-4.5"
        }
        if lowercased.starts(with: "o4-mini") {
            return "o4-mini"
        }
        
        // Extract base name for other models by removing date suffixes
        if let dateRange = lowercased.range(of: "-20[0-9]{2}-[0-9]{2}-[0-9]{2}", options: .regularExpression) {
            return String(lowercased[..<dateRange.lowerBound])
        }
        
        // Remove other common suffixes
        let suffixes = ["-preview", "-latest", "-turbo", "-vision", "-mini", "-realtime", "-audio", "-search", "-tts"]
        var result = lowercased
        
        for suffix in suffixes {
            if let range = result.range(of: suffix) {
                result = String(result[..<range.lowerBound])
            }
        }
        
        return result
    }
    
    /// Filters Claude models to include only those we want to show
    /// - Parameter models: The complete list of models from the API
    /// - Returns: A filtered list of models
    static func filterClaudeModels(_ models: [String]) -> [String] {
        // Priority map for Claude models
        let keyModels = [
            "claude-3-opus": 100,
            "claude-3-5-sonnet": 95,
            "claude-3-sonnet": 90,
            "claude-3-haiku": 85,
            "claude-3-7-sonnet": 97,
            "claude-3-5-haiku": 87
        ]
        
        // Model family extraction regex
        let familyPattern = "claude-([0-9]+(\\.[0-9]+)?)(-(opus|sonnet|haiku))?"
        
        // Group models by family
        var families: [String: [String]] = [:]
        
        // First, categorize models by family with accurate family name extraction
        for model in models {
            let id = model.lowercased()
            
            // Skip non-Claude models
            guard id.contains("claude") else { continue }
            
            // Extract the model family using regex for more accuracy
            var family = "claude-other"
            
            // First try to extract with regex
            if let regex = try? NSRegularExpression(pattern: familyPattern),
               let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) {
                
                // Build the family name from the regex match
                if let mainRange = Range(match.range, in: id) {
                    family = String(id[mainRange])
                }
            } else {
                // Fallback to traditional string-based family detection
                if id.contains("claude-3-opus") {
                    family = "claude-3-opus"
                } else if id.contains("claude-3-7-sonnet") {
                    family = "claude-3-7-sonnet"
                } else if id.contains("claude-3-7-haiku") {
                    family = "claude-3-7-haiku"
                } else if id.contains("claude-3-5-sonnet") {
                    family = "claude-3-5-sonnet"
                } else if id.contains("claude-3-5-haiku") {
                    family = "claude-3-5-haiku"
                } else if id.contains("claude-3-sonnet") {
                    family = "claude-3-sonnet"
                } else if id.contains("claude-3-haiku") {
                    family = "claude-3-haiku"
                } else if id.contains("claude-3") {
                    family = "claude-3"
                } else if id.contains("claude-2") {
                    family = "claude-2"
                }
            }
            
            // Add to appropriate family
            if families[family] == nil {
                families[family] = []
            }
            families[family]?.append(model)
        }
        
        // Log discovered families
        Logger.debug("📋 Found \(families.count) Claude model families")
        
        // Choose one model from each family
        var result: [String] = []
        for (family, members) in families {
            // Sort by our custom priority rules
            let sorted = members.sorted { model1, model2 in
                // Rule 1: Prefer models with dates that include year and month
                let hasFullDate1 = model1.range(of: "\\d{8}", options: .regularExpression) != nil
                let hasFullDate2 = model2.range(of: "\\d{8}", options: .regularExpression) != nil
                
                // Rule 2: For models with dates, prefer newer ones (reverse sort)
                if hasFullDate1 && hasFullDate2 {
                    // Extract dates and compare them
                    if let dateRange1 = model1.range(of: "\\d{8}", options: .regularExpression),
                       let dateRange2 = model2.range(of: "\\d{8}", options: .regularExpression) {
                        let date1 = String(model1[dateRange1])
                        let date2 = String(model2[dateRange2])
                        return date1 > date2
                    }
                }
                
                // Rule 3: Models with dates take priority over those without
                if hasFullDate1 && !hasFullDate2 {
                    return true
                }
                if !hasFullDate1 && hasFullDate2 {
                    return false
                }
                
                // Rule 4: For models without dates, sort by name (shorter names first)
                return model1.count < model2.count
            }
            
            // Add the best representative
            if let bestModel = sorted.first {
                result.append(bestModel)
            }
        }
        
        // Ensure we have the key Claude models if they're in the original list
        for (baseModelName, priority) in keyModels.sorted(by: { $0.value > $1.value }) {
            // Check if any model in the original list contains this base name
            if let bestMatch = models.first(where: { $0.lowercased().contains(baseModelName.lowercased()) }),
               !result.contains(where: { $0.lowercased().contains(baseModelName.lowercased()) }) {
                result.append(bestMatch)
            }
        }
        
        // If we couldn't find any models, use defaults
        if result.isEmpty {
            Logger.debug("⚠️ No Claude models found at all, using defaults")
            return ["claude-3-opus-20240229", "claude-3-sonnet-20240229", 
                    "claude-3-haiku-20240307", "claude-3-5-sonnet-20240620"]
        }
        
        // Log total models
        Logger.debug("📋 Filtered \(models.count) Claude models down to \(result.count) models")
        
        return result.sorted()
    }
    
    /// Filters Grok models to include only those we want to show
    /// - Parameter models: The complete list of models from the API
    /// - Returns: A filtered list of models
    static func filterGrokModels(_ models: [String]) -> [String] {
        // Key Grok models with priority scores
        let keyModels = [
            "grok-1": 100,
            "grok-1.5": 95,
            "grok-1.5-mini": 90,
            "grok-2": 97,
            "grok-2-mini": 92,
            "grok-1-lite": 85
        ]
        
        // First, categorize models by family for better organization
        var families: [String: [String]] = [:]
        
        // First pass: categorize all models by family
        for model in models {
            let id = model.lowercased()
            
            // Skip non-Grok models and deprecated/test models
            guard id.contains("grok") && !id.contains("deprecated") && !id.contains("test") else { continue }
            
            // Extract the family with more precise pattern matching
            let family = extractGrokFamily(id)
            
            // Add to appropriate family
            if families[family] == nil {
                families[family] = []
            }
            families[family]?.append(model)
        }
        
        // Log discovered families
        Logger.debug("📋 Found \(families.count) Grok model families")
        
        // Select the best representative from each family
        var result: [String] = []
        
        for (family, members) in families {
            // Sort family members to find the most canonical version
            let sorted = members.sorted { model1, model2 in
                let id1 = model1.lowercased()
                let id2 = model2.lowercased()
                
                // Rule 1: Prefer exact matches for base models (e.g., "grok-1", "grok-1.5")
                let isExactBaseModel1 = keyModels.keys.contains { id1 == $0 }
                let isExactBaseModel2 = keyModels.keys.contains { id2 == $0 }
                
                if isExactBaseModel1 && !isExactBaseModel2 {
                    return true
                }
                if !isExactBaseModel1 && isExactBaseModel2 {
                    return false
                }
                
                // Rule 2: Prefer models without date/version suffixes
                let hasSuffix1 = containsDateOrSuffix(id1)
                let hasSuffix2 = containsDateOrSuffix(id2)
                
                if !hasSuffix1 && hasSuffix2 {
                    return true
                }
                if hasSuffix1 && !hasSuffix2 {
                    return false
                }
                
                // Rule 3: For models with dates, prefer newer ones
                if id1.contains("-2024") && id2.contains("-2024") {
                    // Date format is likely YYYY-MM-DD, so higher string = newer date
                    return id1 > id2
                }
                
                // Rule 4: Prefer shorter names (cleaner)
                return id1.count < id2.count
            }
            
            // Add the best representative
            if let bestModel = sorted.first {
                result.append(bestModel)
            }
        }
        
        // Ensure we include all key models if they exist in the original list
        for (keyModel, _) in keyModels.sorted(by: { $0.value > $1.value }) {
            if let exactMatch = models.first(where: { $0.lowercased() == keyModel.lowercased() }),
               !result.contains(where: { $0.lowercased() == keyModel.lowercased() }) {
                result.append(exactMatch)
            }
        }
        
        // If we couldn't find any models, use a broader filter
        if result.isEmpty {
            Logger.debug("⚠️ No Grok models matched our filters, using all Grok models")
            result = models.filter { model in
                let id = model.lowercased()
                return id.contains("grok") && !id.contains("deprecated") && !id.contains("test")
            }
        }
        
        // Log total models
        Logger.debug("📋 Filtered \(models.count) Grok models down to \(result.count) models")
        
        return result.sorted()
    }
    
    /// Extracts the standardized family name for a Grok model
    /// - Parameter modelId: The model ID (lowercased)
    /// - Returns: The standardized family name
    private static func extractGrokFamily(_ modelId: String) -> String {
        // Basic pattern for Grok versions - grok-X.Y with optional variant
        let patterns = [
            // Match grok-1, grok-1.5, etc.
            "grok-([0-9](\\.[0-9])?)": "grok-$1",
            // Match suffixed variants like grok-1-mini, grok-1.5-vision
            "grok-([0-9](\\.[0-9])?)-([a-z]+)": "grok-$1-$3"
        ]
        
        // Try each pattern in order
        for (pattern, template) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: modelId, range: NSRange(modelId.startIndex..., in: modelId)) {
                
                // Extract captured groups
                var capturedGroups: [String] = []
                
                // Get all capture groups
                for i in 0..<match.numberOfRanges {
                    if let range = Range(match.range(at: i), in: modelId) {
                        capturedGroups.append(String(modelId[range]))
                    } else {
                        capturedGroups.append("")
                    }
                }
                
                // Replace $n placeholders in template with captured groups
                var result = template
                for i in 1..<capturedGroups.count {
                    result = result.replacingOccurrences(of: "$\(i)", with: capturedGroups[i])
                }
                
                return result
            }
        }
        
        // Fallback: handle special cases
        if modelId.contains("-mini") {
            return "grok-mini"
        } else if modelId.contains("-vision") {
            return "grok-vision"
        } else if modelId.contains("-fast") {
            return "grok-fast"
        } else if modelId.contains("-lite") {
            return "grok-lite"
        }
        
        // Last resort
        return "grok-other"
    }
    
    /// Checks if a model name contains a date or special suffix
    /// - Parameter modelName: The model name to check
    /// - Returns: True if the model has a date or special suffix
    private static func containsDateOrSuffix(_ modelName: String) -> Bool {
        let suffixes = ["-vision", "-image", "-mini", "-fast", "-1212", "-2023", "-2024", "-2025"]
        let id = modelName.lowercased()
        
        for suffix in suffixes {
            if id.contains(suffix) {
                return true
            }
        }
        
        // Check for date pattern like 2024-09-12
        let datePattern = "\\d{4}-\\d{2}-\\d{2}"
        return id.range(of: datePattern, options: .regularExpression) != nil
    }
    
    /// Extracts a numeric version from a model name for sorting
    /// - Parameter modelName: The model name
    /// - Returns: A numeric version (defaults to 0 if not found)
    private static func extractVersionNumber(_ modelName: String) -> Double {
        let id = modelName.lowercased()
        
        // Look for patterns like "grok-1", "grok-2", "grok-3.5"
        let versionPattern = "grok-(\\d+(\\.\\d+)?)"
        if let regex = try? NSRegularExpression(pattern: versionPattern),
           let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
           let range = Range(match.range(at: 1), in: id) {
            
            let versionString = String(id[range])
            return Double(versionString) ?? 0.0
        }
        
        return 0.0
    }
    
    /// Filters Gemini models to include only those we want to show
    /// - Parameter models: The complete list of models from the API
    /// - Returns: A filtered list of models
    static func filterGeminiModels(_ models: [String]) -> [String] {
        // Key Gemini models with priority scores
        let keyModels = [
            "gemini-1.5-pro": 100,
            "gemini-1.5-flash": 95,
            "gemini-pro": 90,
            "gemini-1.0-pro": 85,
            "gemini-2.0-pro": 97,
            "gemini-2.0-flash": 96,
            "gemini-1.5-flash-8b": 94
        ]
        
        // First, categorize models by standardized families
        var families: [String: [String]] = [:]
        
        // First pass: categorize all models by family
        for model in models {
            let id = model.lowercased()
            
            // Skip non-Gemini models and models we don't want
            guard id.contains("gemini") && !id.contains("embedding") else { continue }
            
            // Skip specialized variants to keep the list clean
            if id.contains("gemma-") || 
               id.contains("-tuning") || 
               id.contains("-thinking") || 
               id.contains("-exp-") ||
               id.contains("playground") {
                continue
            }
            
            // Extract the standardized family name
            let family = extractGeminiFamily(id)
            
            // Add to appropriate family
            if families[family] == nil {
                families[family] = []
            }
            families[family]?.append(model)
        }
        
        // Log discovered families
        Logger.debug("📋 Found \(families.count) Gemini model families")
        
        // Select the best representative from each family
        var result: [String] = []
        
        for (family, members) in families {
            // Sort models within each family using combined approach
            let sorted = members.sorted { model1, model2 in
                let id1 = model1.lowercased()
                let id2 = model2.lowercased()
                
                // Rule 1: Prefer exact matches for key models
                let isExactKeyModel1 = keyModels.keys.contains { id1 == $0 }
                let isExactKeyModel2 = keyModels.keys.contains { id2 == $0 }
                
                if isExactKeyModel1 && !isExactKeyModel2 {
                    return true
                }
                if !isExactKeyModel1 && isExactKeyModel2 {
                    return false
                }
                
                // Rule 2: If both are key models, use priority from keyModels
                if isExactKeyModel1 && isExactKeyModel2 {
                    let priority1 = keyModels[id1] ?? 0
                    let priority2 = keyModels[id2] ?? 0
                    return priority1 > priority2
                }
                
                // Rule 3: Prefer models with "-latest" suffix
                let hasLatest1 = id1.contains("-latest")
                let hasLatest2 = id2.contains("-latest")
                
                if hasLatest1 && !hasLatest2 {
                    return true
                }
                if !hasLatest1 && hasLatest2 {
                    return false
                }
                
                // Rule 4: For models with dates, prefer newer dates
                if id1.contains("-20") && id2.contains("-20") {
                    return id1 > id2 // Reverse sort for dates
                }
                
                // Rule 5: Prefer models without dates over dated models (unless latest)
                if !id1.contains("-20") && id2.contains("-20") {
                    return true
                }
                if id1.contains("-20") && !id2.contains("-20") {
                    return false
                }
                
                // Rule 6: Prefer shorter names (cleaner)
                return id1.count < id2.count
            }
            
            // Add the best representative
            if let bestModel = sorted.first {
                result.append(bestModel)
            }
        }
        
        // Ensure we have all key models if they exist in the original list
        for (keyModel, _) in keyModels.sorted(by: { $0.value > $1.value }) {
            if let exactMatch = models.first(where: { $0.lowercased() == keyModel.lowercased() }),
               !result.contains(where: { $0.lowercased() == keyModel.lowercased() }) {
                result.append(exactMatch)
            }
        }
        
        // If we couldn't find any models, use default fallbacks
        if result.isEmpty {
            Logger.debug("⚠️ No Gemini models matched our filters, using defaults")
            return ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-pro"]
        }
        
        // Log total models
        Logger.debug("📋 Filtered \(models.count) Gemini models down to \(result.count) models")
        
        return result.sorted()
    }
    
    /// Extracts a standardized family name for a Gemini model
    /// - Parameter modelId: The model ID (lowercase)
    /// - Returns: A standardized family name
    private static func extractGeminiFamily(_ modelId: String) -> String {
        // Common patterns for Gemini model families
        let familyPatterns = [
            // Match gemini-X.Y-variant pattern (e.g., gemini-1.5-pro)
            "gemini-([0-9]+(\\.[0-9]+)?)-([a-z]+)": "gemini-$1-$3",
            // Match basic gemini-X.Y pattern
            "gemini-([0-9]+(\\.[0-9]+)?)": "gemini-$1",
            // Match gemini-variant pattern (e.g., gemini-pro)
            "gemini-([a-z]+)": "gemini-$1"
        ]
        
        // Try each pattern in order
        for (pattern, template) in familyPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: modelId, range: NSRange(modelId.startIndex..., in: modelId)) {
                
                // Extract captured groups
                var capturedGroups: [String] = []
                
                // Get all capture groups
                for i in 0..<match.numberOfRanges {
                    if let range = Range(match.range(at: i), in: modelId) {
                        capturedGroups.append(String(modelId[range]))
                    } else {
                        capturedGroups.append("")
                    }
                }
                
                // Replace $n placeholders in template with captured groups
                var result = template
                for i in 1..<capturedGroups.count {
                    result = result.replacingOccurrences(of: "$\(i)", with: capturedGroups[i])
                }
                
                return result
            }
        }
        
        // Fallback for special cases
        if modelId.contains("-vision") {
            return "gemini-vision"
        } else if modelId.contains("-image") {
            return "gemini-image"
        }
        
        // Last resort
        return "gemini-other"
    }
    
    // MARK: - Advanced Model Filtering with RegEx
    
    /// Filters OpenAI model IDs to pick base names or first variant for each model family
    /// - Parameter modelList: List of raw model IDs
    /// - Returns: Filtered list of model IDs
    static func advancedFilterOpenAIModels(_ modelList: [String]) -> [String] {
        // Just delegate to our improved implementation
        return filterOpenAIModels(modelList)
    }
    
    /// Filters Claude model IDs to pick only the latest version of each model family
    /// - Parameter modelList: List of raw model IDs
    /// - Returns: Filtered list of model IDs
    static func advancedFilterClaudeModels(_ modelList: [String]) -> [String] {
        // Just delegate to our improved implementation
        return filterClaudeModels(modelList)
    }
    
    /// Filters Grok model IDs to pick latest version of each model family
    /// - Parameter modelList: List of raw model IDs
    /// - Returns: Filtered list of model IDs
    static func advancedFilterGrokModels(_ modelList: [String]) -> [String] {
        // Just delegate to our improved implementation
        return filterGrokModels(modelList)
    }
    
    /// Filters Gemini model IDs to pick base names (or latest)
    /// - Parameter modelList: List of raw model IDs
    /// - Returns: Filtered list of model IDs
    static func advancedFilterGeminiModels(_ modelList: [String]) -> [String] {
        // Just delegate to our improved implementation
        return filterGeminiModels(modelList)
    }
}
