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
            // Logger.debug("⚠️ API key for \(provider) is empty or 'none'") // Assuming Logger exists
            print("⚠️ API key for \(provider) is empty or 'none'")
            return nil
        }

        // Check format based on provider
        switch provider {
            case AIModels.Provider.openai: // Assuming AIModels.Provider struct/enum exists
                if (!cleanKey.hasPrefix("sk-") && !cleanKey.hasPrefix("sk-proj-")) || cleanKey.count < 40 {
                    // Logger.debug("⚠️ OpenAI API key has invalid format (should start with 'sk-' or 'sk-proj-' and be at least 40 chars)")
                    print("⚠️ OpenAI API key has invalid format (should start with 'sk-' or 'sk-proj-' and be at least 40 chars)")
                    return nil
                }

            case AIModels.Provider.claude:
                if !cleanKey.hasPrefix("sk-ant-") || cleanKey.count < 60 {
                    // Logger.debug("⚠️ Claude API key has invalid format (should start with 'sk-ant-' and be at least 60 chars)")
                    print("⚠️ Claude API key has invalid format (should start with 'sk-ant-' and be at least 60 chars)")
                    return nil
                }

            case AIModels.Provider.grok:
                if (!cleanKey.hasPrefix("gsk_") && !cleanKey.hasPrefix("xai-")) || cleanKey.count < 30 {
                    // Logger.debug("⚠️ Grok API key has invalid format (should start with 'gsk_' or 'xai-' and be at least 30 chars)")
                    print("⚠️ Grok API key has invalid format (should start with 'gsk_' or 'xai-' and be at least 30 chars)")
                    return nil
                }

            case AIModels.Provider.gemini:
                if !cleanKey.hasPrefix("AIza") || cleanKey.count < 20 {
                    // Logger.debug("⚠️ Gemini API key has invalid format (should start with 'AIza' and be at least 20 chars)")
                    print("⚠️ Gemini API key has invalid format (should start with 'AIza' and be at least 20 chars)")
                    return nil
                }

            default:
                if cleanKey.count < 20 {
                    // Logger.debug("⚠️ API key for \(provider) is too short (length < 20)")
                    print("⚠️ API key for \(provider) is too short (length < 20)")
                    return nil
                }
        }

        // Log successful validation (without revealing the key)
        let firstChars = String(cleanKey.prefix(4))
        let length = cleanKey.count
        // Logger.debug("✅ Valid API key format for \(provider): First chars: \(firstChars), Length: \(length)")
        print("✅ Valid API key format for \(provider): First chars: \(firstChars), Length: \(length)")

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
                if (apiKey.hasPrefix("sk-") || apiKey.hasPrefix("sk-proj-")) && apiKey.count >= 40 {
                    return .valid
                }

            case AIModels.Provider.claude:
                if apiKey.hasPrefix("sk-ant-") && apiKey.count >= 60 {
                    return .valid
                }

            case AIModels.Provider.grok:
                if (apiKey.hasPrefix("gsk_") || apiKey.hasPrefix("xai-")) && apiKey.count >= 30 {
                    return .valid
                }

            case AIModels.Provider.gemini:
                if apiKey.hasPrefix("AIza") && apiKey.count >= 20 {
                    return .valid
                }

            default:
                if apiKey.count >= 20 {
                    return .valid
                }
        }

        return .invalid
    }

    // New private helper function to get a canonical model name
    private static func getCanonicalOpenAIModelName(_ modelIdentifier: String) -> String {
        var name = modelIdentifier.lowercased()

        // 1. Remove date suffixes (e.g., -YYYY-MM-DD, -MMDD, -YYYYMMDD from the end)
        // Handles formats like -2024-12-17, -20241217, -1217
        if let dateRegex = try? NSRegularExpression(pattern: "-(?:20\\d{2}-\\d{2}-\\d{2}|\\d{6}|\\d{4})$") {
            name = dateRegex.stringByReplacingMatches(in: name, options: [], range: NSRange(name.startIndex..., in: name), withTemplate: "")
        }

        // 2. Specific transformation for "chatgpt-..." models
        if name.starts(with: "chatgpt-") && name.hasSuffix("-latest") {
            name = name.replacingOccurrences(of: "chatgpt-", with: "gpt-") // "gpt-4o-latest"
            name = String(name.dropLast("-latest".count)) // "gpt-4o"
        }

        // 3. Define suffixes to strip. Order can be important (longer, more specific ones first).
        // These are suffixes that are NOT part of the desired canonical forms.
        let suffixesToStrip = [
            // Compound suffixes first
            "-realtime-preview", "-audio-preview", "-search-preview",
            "-instruct-0914",
            "-1106-preview", "-turbo-preview",
            // Single generic suffixes
            "-realtime", "-audio", "-search", "-vision", "-transcribe", "-tts",
            "-instruct", "-turbo", "-latest",
            // Version numbers that are not part of X.Y structure
            "-0914", "-0125", "-1106", "-0613", "-16k", "-32k",
        ]

        var currentName = name
        for suffix in suffixesToStrip {
            if currentName.hasSuffix(suffix) {
                currentName = String(currentName.dropLast(suffix.count))
            }
        }

        // 4. Handle -preview, -mini, -nano last, with context, after other suffixes are gone.
        // Strip "-preview" unless it's the "gpt-X.Y-preview" form
        if currentName.hasSuffix("-preview") {
            let isDesiredPreviewPattern = "^gpt-[0-9]+\\.[0-9]+-preview$"
            // Check if currentName matches the desired gpt-N.M-preview pattern
            var isMatch = false
            if let regex = try? NSRegularExpression(pattern: isDesiredPreviewPattern) {
                if regex.firstMatch(in: currentName, options: [], range: NSRange(currentName.startIndex..., in: currentName)) != nil {
                    isMatch = true
                }
            }
            if !isMatch {
                currentName = String(currentName.dropLast("-preview".count))
            }
        }

        // Strip "-mini" unless it's the "oX-mini" form
        if currentName.hasSuffix("-mini") {
            let isDesiredMiniPattern = "^o[0-9]+-mini$"
            var isMatch = false
            if let regex = try? NSRegularExpression(pattern: isDesiredMiniPattern) {
                if regex.firstMatch(in: currentName, options: [], range: NSRange(currentName.startIndex..., in: currentName)) != nil {
                    isMatch = true
                }
            }
            if !isMatch {
                currentName = String(currentName.dropLast("-mini".count))
            }
        }

        // Strip "-nano" always, as it's not in any desired pattern
        if currentName.hasSuffix("-nano") {
            currentName = String(currentName.dropLast("-nano".count))
        }

        return currentName
    }

    /// Filters OpenAI models to include only those we want to show
    /// - Parameter models: The complete list of models from the API
    /// - Returns: A filtered list of models
    static func filterOpenAIModels(_ models: [String]) -> [String] {
        // Regex for desired final model patterns
        // Covers: gpt-N, gpt-N.M, gpt-No, gpt-N.M (o is optional for N.M), gpt-N.M-preview, oN, oN-mini
        let desiredShapeRegexPattern = "^(gpt-(?:(?:[0-9]+(?:\\.[0-9]+)?)(?:o)?|[0-9]+\\.[0-9]+-preview)|o[0-9]+(?:-mini)?)$"
        guard let desiredShapeRegex = try? NSRegularExpression(pattern: desiredShapeRegexPattern) else {
            // Logger.error("Error: Invalid regex for desired OpenAI model shapes.") // Assuming Logger exists
            print("Error: Invalid regex for desired OpenAI model shapes.")
            return models.sorted()
        }

        let undesiredSubstrings = [
            "embedding", "whisper", "dall-e", "text-moderation",
            "babbage", "davinci", "curie", "ada",
            "gemma", "playground", "codex", "computer-use", "omni-moderation"
        ]

        // Models to explicitly exclude after canonicalization and regex matching
        let excludedModels = Set(["o1", "o1-mini"])

        var finalModelSet = Set<String>()

        for modelName in models {
            let lowercasedModelName = modelName.lowercased()

            var skip = false
            for undesired in undesiredSubstrings {
                if lowercasedModelName.contains(undesired) {
                    skip = true
                    break
                }
            }
            if skip {
                continue
            }

            let canonicalName = getCanonicalOpenAIModelName(lowercasedModelName)

            if desiredShapeRegex.firstMatch(in: canonicalName, options: [], range: NSRange(canonicalName.startIndex..., in: canonicalName)) != nil {
                // Add to set only if not in the excludedModels list
                if !excludedModels.contains(canonicalName) {
                    finalModelSet.insert(canonicalName)
                }
            }
        }

        // Logger.debug("📋 Filtered \(models.count) OpenAI models down to \(finalModelSet.count) base models: \(finalModelSet.sorted().joined(separator: ", "))")
        print("📋 Filtered \(models.count) OpenAI models down to \(finalModelSet.count) base models: \(finalModelSet.sorted().joined(separator: ", "))")
        return finalModelSet.sorted()
    }

    /// Checks if a model ID exactly matches one of our defined base models
    /// - Parameter modelId: The model ID to check
    /// - Returns: True if it's an exact match for a base model
    private static func exactlyMatchesBaseModel(_ modelId: String) -> Bool {
        // This function might need to be updated or deprecated if not used by the new filter logic extensively.
        // The new filter relies on regex and canonical names.
        let baseModels = [ // Based on original code, adjust if needed
            "gpt-4", "gpt-4o", "gpt-3.5-turbo", "gpt-4-turbo", "gpt-4.5-turbo", // gpt-4.5-turbo wasn't in desired user list
            "o1", "o1-mini", "o1-preview", "o3", "o3-mini", "o3-nano", "o4-mini"
        ]
        return baseModels.contains(modelId.lowercased())
    }

    /// Determines if a model name is a "base" model without version suffixes
    /// - Parameter modelName: The model name to check
    /// - Returns: True if this is a base model
    private static func isBaseModel(_ modelName: String) -> Bool {
        // This function might also need review based on the new filter logic.
        let baseModels = ["gpt-4", "gpt-4o", "gpt-3.5-turbo", "o1", "o3", "o3-mini", "o3-nano", "o4-mini"]
        return baseModels.contains(modelName.lowercased())
    }

    /// Extracts the base name of a model (e.g., "gpt-4o-2024-05-13" -> "gpt-4o")
    /// - Parameter modelName: The full model name
    /// - Returns: The base model name
    private static func getBaseModelName(_ modelName: String) -> String {
        // This is the OLD getBaseModelName. The new OpenAI filter uses getCanonicalOpenAIModelName.
        // This function might still be used by other filters (Claude, Grok, Gemini) and may need
        // to remain, or those filters also need updating.
        // For the purpose of THIS request, only filterOpenAIModels and its helper were changed.
        let lowercased = modelName.lowercased()

        if lowercased.starts(with: "gpt-4.5-preview") { // User wants "gpt-4.5-preview"
                                                        // Check if the original only has date suffix after "gpt-4.5-preview"
            if let dateRegex = try? NSRegularExpression(pattern: "-(?:20\\d{2}-\\d{2}-\\d{2}|\\d{6}|\\d{4})$") {
                let nameWithoutDate = dateRegex.stringByReplacingMatches(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased), withTemplate: "")
                if nameWithoutDate == "gpt-4.5-preview" {
                    return "gpt-4.5-preview"
                }
            }
            // Fallback for other gpt-4.5-preview variants if needed, or general stripping
        }

        if lowercased.starts(with: "o4-mini") { // User wants "o4-mini"
            if let dateRegex = try? NSRegularExpression(pattern: "-(?:20\\d{2}-\\d{2}-\\d{2}|\\d{6}|\\d{4})$") {
                let nameWithoutDate = dateRegex.stringByReplacingMatches(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased), withTemplate: "")
                if nameWithoutDate == "o4-mini" {
                    return "o4-mini"
                }
            }
        }

        // Extract base name for other models by removing date suffixes
        if let dateRange = lowercased.range(of: "-20[0-9]{2}-[0-9]{2}-[0-9]{2}", options: .regularExpression) {
            var base = String(lowercased[..<dateRange.lowerBound])
            // If base is now "gpt-4.5-preview", return it.
            if base == "gpt-4.5-preview" { return base }
            // If base is now "oX-mini", return it.
            if (try? NSRegularExpression(pattern: "^o[0-9]+-mini$").firstMatch(in: base, options: [], range: NSRange(base.startIndex..., in: base))) != nil {
                return base
            }
            // Continue with general suffix stripping for this 'base'
            let suffixes = ["-preview", "-latest", "-turbo", "-vision", "-mini", "-realtime", "-audio", "-search", "-tts"]
            for suffix in suffixes {
                if base.hasSuffix(suffix) {
                    // Don't strip -preview from gpt-4.5-preview
                    if suffix == "-preview" && base == "gpt-4.5-preview" { continue }
                    // Don't strip -mini from oX-mini
                    if suffix == "-mini" && (try? NSRegularExpression(pattern: "^o[0-9]+-mini$").firstMatch(in: base, options: [], range: NSRange(base.startIndex..., in: base))) != nil {
                        continue
                    }
                    base = String(base.dropLast(suffix.count))
                }
            }
            return base
        }

        // If no YYYY-MM-DD date format, try stripping other suffixes
        var result = lowercased
        let suffixes = ["-preview", "-latest", "-turbo", "-vision", "-mini", "-realtime", "-audio", "-search", "-tts"]

        for suffix in suffixes {
            if result.hasSuffix(suffix) {
                // Don't strip -preview from gpt-4.5-preview
                if suffix == "-preview" && result == "gpt-4.5-preview" { continue }
                // Don't strip -mini from oX-mini
                if suffix == "-mini" && (try? NSRegularExpression(pattern: "^o[0-9]+-mini$").firstMatch(in: result, options: [], range: NSRange(result.startIndex..., in: result))) != nil {
                    continue
                }
                result = String(result.dropLast(suffix.count))
            }
        }
        return result
    }

    /// Filters Claude models to include only those we want to show
    /// - Parameter models: The complete list of models from the API
    /// - Returns: A filtered list of models
    static func filterClaudeModels(_ models: [String]) -> [String] {
        // This function is unchanged as per the request.
        // Logger.debug("Filtering Claude models...") // Placeholder for actual logging
        print("Filtering Claude models...")
        let keyModels = [
            "claude-3-opus": 100,
            "claude-3-5-sonnet": 95,
            "claude-3-sonnet": 90,
            "claude-3-haiku": 85,
            "claude-3-7-sonnet": 97,
            "claude-3-5-haiku": 87
        ]
        let familyPattern = "claude-([0-9]+(\\.[0-9]+)?)(-(opus|sonnet|haiku))?"
        var families: [String: [String]] = [:]
        for model in models {
            let id = model.lowercased()
            guard id.contains("claude") else { continue }
            var family = "claude-other"
            if let regex = try? NSRegularExpression(pattern: familyPattern),
               let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) {
                if let mainRange = Range(match.range, in: id) {
                    family = String(id[mainRange])
                }
            } else {
                if id.contains("claude-3-opus") { family = "claude-3-opus" }
                else if id.contains("claude-3-7-sonnet") { family = "claude-3-7-sonnet"}
                else if id.contains("claude-3-7-haiku") { family = "claude-3-7-haiku"}
                else if id.contains("claude-3-5-sonnet") { family = "claude-3-5-sonnet" }
                else if id.contains("claude-3-5-haiku") { family = "claude-3-5-haiku"}
                else if id.contains("claude-3-sonnet") { family = "claude-3-sonnet" }
                else if id.contains("claude-3-haiku") { family = "claude-3-haiku" }
                else if id.contains("claude-3") { family = "claude-3" }
                else if id.contains("claude-2") { family = "claude-2" }
            }
            if families[family] == nil { families[family] = [] }
            families[family]?.append(model)
        }
        // Logger.debug("📋 Found \(families.count) Claude model families")
        print("📋 Found \(families.count) Claude model families")
        var result: [String] = []
        for (_, members) in families {
            let sorted = members.sorted { model1, model2 in
                let hasFullDate1 = model1.range(of: "\\d{8}", options: .regularExpression) != nil
                let hasFullDate2 = model2.range(of: "\\d{8}", options: .regularExpression) != nil
                if hasFullDate1 && hasFullDate2 {
                    if let dateRange1 = model1.range(of: "\\d{8}", options: .regularExpression),
                       let dateRange2 = model2.range(of: "\\d{8}", options: .regularExpression) {
                        return String(model1[dateRange1]) > String(model2[dateRange2])
                    }
                }
                if hasFullDate1 && !hasFullDate2 { return true }
                if !hasFullDate1 && hasFullDate2 { return false }
                return model1.count < model2.count
            }
            if let bestModel = sorted.first { result.append(bestModel) }
        }
        for (baseModelName, _) in keyModels.sorted(by: { $0.value > $1.value }) {
            if let bestMatch = models.first(where: { $0.lowercased().contains(baseModelName.lowercased()) }),
               !result.contains(where: { $0.lowercased().contains(baseModelName.lowercased()) }) {
                result.append(bestMatch)
            }
        }
        if result.isEmpty {
            // Logger.debug("⚠️ No Claude models found at all, using defaults")
            print("⚠️ No Claude models found at all, using defaults")
            return ["claude-3-opus-20240229", "claude-3-sonnet-20240229",
                    "claude-3-haiku-20240307", "claude-3-5-sonnet-20240620"]
        }
        // Logger.debug("📋 Filtered \(models.count) Claude models down to \(result.count) models")
        print("📋 Filtered \(models.count) Claude models down to \(result.count) models")
        return result.sorted()
    }

    /// Filters Grok models to include only those we want to show
    /// - Parameter models: The complete list of models from the API
    /// - Returns: A filtered list of models
    static func filterGrokModels(_ models: [String]) -> [String] {
        // This function is unchanged as per the request.
        // Logger.debug("Filtering Grok models...") // Placeholder
        print("Filtering Grok models...")
        let keyModels = [
            "grok-1": 100, "grok-1.5": 95, "grok-1.5-mini": 90,
            "grok-2": 97, "grok-2-mini": 92, "grok-1-lite": 85
        ]
        var families: [String: [String]] = [:]
        for model in models {
            let id = model.lowercased()
            guard id.contains("grok") && !id.contains("deprecated") && !id.contains("test") else { continue }
            let family = extractGrokFamily(id) // Assumes extractGrokFamily is defined and correct
            if families[family] == nil { families[family] = [] }
            families[family]?.append(model)
        }
        // Logger.debug("📋 Found \(families.count) Grok model families")
        print("📋 Found \(families.count) Grok model families")
        var result: [String] = []
        for (_, members) in families {
            let sorted = members.sorted { model1, model2 in
                let id1 = model1.lowercased(); let id2 = model2.lowercased()
                let isExactBaseModel1 = keyModels.keys.contains { id1 == $0 }
                let isExactBaseModel2 = keyModels.keys.contains { id2 == $0 }
                if isExactBaseModel1 && !isExactBaseModel2 { return true }
                if !isExactBaseModel1 && isExactBaseModel2 { return false }
                let hasSuffix1 = containsDateOrSuffix(id1); let hasSuffix2 = containsDateOrSuffix(id2) // Assumes containsDateOrSuffix is defined
                if !hasSuffix1 && hasSuffix2 { return true }
                if hasSuffix1 && !hasSuffix2 { return false }
                if id1.contains("-2024") && id2.contains("-2024") { return id1 > id2 }
                return id1.count < id2.count
            }
            if let bestModel = sorted.first { result.append(bestModel) }
        }
        for (keyModel, _) in keyModels.sorted(by: { $0.value > $1.value }) {
            if let exactMatch = models.first(where: { $0.lowercased() == keyModel.lowercased() }),
               !result.contains(where: { $0.lowercased() == keyModel.lowercased() }) {
                result.append(exactMatch)
            }
        }
        if result.isEmpty {
            // Logger.debug("⚠️ No Grok models matched our filters, using all Grok models")
            print("⚠️ No Grok models matched our filters, using all Grok models")
            result = models.filter { $0.lowercased().contains("grok") && !$0.lowercased().contains("deprecated") && !$0.lowercased().contains("test") }
        }
        // Logger.debug("📋 Filtered \(models.count) Grok models down to \(result.count) models")
        print("📋 Filtered \(models.count) Grok models down to \(result.count) models")
        return result.sorted()
    }
    private static func extractGrokFamily(_ modelId: String) -> String {
        // This is the OLD extractGrokFamily. Assumed to be correct by filterGrokModels.
        let patterns = [
            "grok-([0-9](\\.[0-9])?)": "grok-$1",
            "grok-([0-9](\\.[0-9])?)-([a-z]+)": "grok-$1-$3"
        ]
        for (pattern, template) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: modelId, range: NSRange(modelId.startIndex..., in: modelId)) {
                var capturedGroups: [String] = []
                for i in 0..<match.numberOfRanges {
                    if let range = Range(match.range(at: i), in: modelId) { capturedGroups.append(String(modelId[range])) }
                    else { capturedGroups.append("") }
                }
                var result = template
                for i in 1..<capturedGroups.count { result = result.replacingOccurrences(of: "$\(i)", with: capturedGroups[i]) }
                return result
            }
        }
        if modelId.contains("-mini") { return "grok-mini" }
        else if modelId.contains("-vision") { return "grok-vision" }
        else if modelId.contains("-fast") { return "grok-fast" }
        else if modelId.contains("-lite") { return "grok-lite" }
        return "grok-other"
    }

    private static func containsDateOrSuffix(_ modelName: String) -> Bool {
        // This is the OLD containsDateOrSuffix. Assumed to be correct by filterGrokModels.
        let suffixes = ["-vision", "-image", "-mini", "-fast", "-1212", "-2023", "-2024", "-2025"]
        let id = modelName.lowercased()
        for suffix in suffixes { if id.contains(suffix) { return true } }
        let datePattern = "\\d{4}-\\d{2}-\\d{2}"
        return id.range(of: datePattern, options: .regularExpression) != nil
    }

    /// Filters Gemini models to include only those we want to show
    /// - Parameter models: The complete list of models from the API
    /// - Returns: A filtered list of models
    static func filterGeminiModels(_ models: [String]) -> [String] {
        // This function is unchanged as per the request.
        // Logger.debug("Filtering Gemini models...") // Placeholder
        print("Filtering Gemini models...")
        let keyModels = [
            "gemini-1.5-pro": 100, "gemini-1.5-flash": 95, "gemini-pro": 90,
            "gemini-1.0-pro": 85, "gemini-2.0-pro": 97, "gemini-2.0-flash": 96,
            "gemini-1.5-flash-8b": 94
        ]
        var families: [String: [String]] = [:]
        for model in models {
            let id = model.lowercased()
            guard id.contains("gemini") && !id.contains("embedding") else { continue }
            if id.contains("gemma-") || id.contains("-tuning") || id.contains("-thinking") ||
                id.contains("-exp-") || id.contains("playground") { continue }
            let family = extractGeminiFamily(id) // Assumes extractGeminiFamily is defined
            if families[family] == nil { families[family] = [] }
            families[family]?.append(model)
        }
        // Logger.debug("📋 Found \(families.count) Gemini model families")
        print("📋 Found \(families.count) Gemini model families")
        var result: [String] = []
        for (_, members) in families {
            let sorted = members.sorted { model1, model2 in
                let id1 = model1.lowercased(); let id2 = model2.lowercased()
                let isExactKeyModel1 = keyModels.keys.contains { id1 == $0 }
                let isExactKeyModel2 = keyModels.keys.contains { id2 == $0 }
                if isExactKeyModel1 && !isExactKeyModel2 { return true }
                if !isExactKeyModel1 && isExactKeyModel2 { return false }
                if isExactKeyModel1 && isExactKeyModel2 { return (keyModels[id1] ?? 0) > (keyModels[id2] ?? 0) }
                let hasLatest1 = id1.contains("-latest"); let hasLatest2 = id2.contains("-latest")
                if hasLatest1 && !hasLatest2 { return true }
                if !hasLatest1 && hasLatest2 { return false }
                if id1.contains("-20") && id2.contains("-20") { return id1 > id2 }
                if !id1.contains("-20") && id2.contains("-20") { return true }
                if id1.contains("-20") && !id2.contains("-20") { return false }
                return id1.count < id2.count
            }
            if let bestModel = sorted.first { result.append(bestModel) }
        }
        for (keyModel, _) in keyModels.sorted(by: { $0.value > $1.value }) {
            if let exactMatch = models.first(where: { $0.lowercased() == keyModel.lowercased() }),
               !result.contains(where: { $0.lowercased() == keyModel.lowercased() }) {
                result.append(exactMatch)
            }
        }
        if result.isEmpty {
            // Logger.debug("⚠️ No Gemini models matched our filters, using defaults")
            print("⚠️ No Gemini models matched our filters, using defaults")
            return ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-pro"]
        }
        // Logger.debug("📋 Filtered \(models.count) Gemini models down to \(result.count) models")
        print("📋 Filtered \(models.count) Gemini models down to \(result.count) models")
        return result.sorted()
    }

    private static func extractGeminiFamily(_ modelId: String) -> String {
        // This is the OLD extractGeminiFamily. Assumed to be correct by filterGeminiModels.
        let familyPatterns = [
            "gemini-([0-9]+(\\.[0-9]+)?)-([a-z]+)": "gemini-$1-$3",
            "gemini-([0-9]+(\\.[0-9]+)?)": "gemini-$1",
            "gemini-([a-z]+)": "gemini-$1"
        ]
        for (pattern, template) in familyPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: modelId, range: NSRange(modelId.startIndex..., in: modelId)) {
                var capturedGroups: [String] = []
                for i in 0..<match.numberOfRanges {
                    if let range = Range(match.range(at: i), in: modelId) { capturedGroups.append(String(modelId[range])) }
                    else { capturedGroups.append("") }
                }
                var result = template
                for i in 1..<capturedGroups.count { result = result.replacingOccurrences(of: "$\(i)", with: capturedGroups[i]) }
                return result
            }
        }
        if modelId.contains("-vision") { return "gemini-vision" }
        else if modelId.contains("-image") { return "gemini-image" }
        return "gemini-other"
    }

    // MARK: - Advanced Model Filtering with RegEx
    // These now use the updated filters above.

    static func advancedFilterOpenAIModels(_ modelList: [String]) -> [String] {
        return filterOpenAIModels(modelList)
    }

    static func advancedFilterClaudeModels(_ modelList: [String]) -> [String] {
        return filterClaudeModels(modelList)
    }

    static func advancedFilterGrokModels(_ modelList: [String]) -> [String] {
        return filterGrokModels(modelList)
    }

    static func advancedFilterGeminiModels(_ modelList: [String]) -> [String] {
        return filterGeminiModels(modelList)
    }
}

