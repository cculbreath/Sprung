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

    // Helper function for OpenAI model name canonicalization
    private static func getCanonicalOpenAIModelName(_ modelIdentifier: String) -> String {
        var name = modelIdentifier.lowercased()
        if let dateRegex = try? NSRegularExpression(pattern: "-(?:20\\d{2}-\\d{2}-\\d{2}|\\d{6}|\\d{4})$") {
            name = dateRegex.stringByReplacingMatches(in: name, options: [], range: NSRange(name.startIndex..., in: name), withTemplate: "")
        }
        // Normalize OpenAI reasoning mini model naming variants to 'o4-mini'
        if name == "o4-mini" || name == "4o-mini" || name == "gpt4o-mini" || name == "gpt-4o-mini" {
            return "o4-mini"
        }
        if name.starts(with: "chatgpt-") && name.hasSuffix("-latest") {
            name = name.replacingOccurrences(of: "chatgpt-", with: "gpt-")
            name = String(name.dropLast("-latest".count))
        }
        let suffixesToStrip = [
            "-realtime-preview", "-audio-preview", "-search-preview",
            "-instruct-0914", "-1106-preview", "-turbo-preview",
            "-realtime", "-audio", "-search", "-vision", "-transcribe", "-tts",
            "-instruct", "-turbo", "-latest",
            "-0914", "-0125", "-1106", "-0613", "-16k", "-32k",
        ]
        var currentName = name
        for suffix in suffixesToStrip {
            if currentName.hasSuffix(suffix) {
                currentName = String(currentName.dropLast(suffix.count))
            }
        }
        if currentName.hasSuffix("-preview") {
            let isDesiredPreviewPattern = "^gpt-[0-9]+\\.[0-9]+-preview$"
            var isMatch = false
            if let regex = try? NSRegularExpression(pattern: isDesiredPreviewPattern) {
                if regex.firstMatch(in: currentName, options: [], range: NSRange(currentName.startIndex..., in: currentName)) != nil {
                    isMatch = true
                }
            }
            if !isMatch { currentName = String(currentName.dropLast("-preview".count)) }
        }
        if currentName.hasSuffix("-mini") {
            let isDesiredMiniPattern = "^o[0-9]+-mini$"
            var isMatch = false
            if let regex = try? NSRegularExpression(pattern: isDesiredMiniPattern) {
                if regex.firstMatch(in: currentName, options: [], range: NSRange(currentName.startIndex..., in: currentName)) != nil {
                    isMatch = true
                }
            }
            if !isMatch { currentName = String(currentName.dropLast("-mini".count)) }
        }
        if currentName.hasSuffix("-nano") {
            currentName = String(currentName.dropLast("-nano".count))
        }
        return currentName
    }

    /// Filters OpenAI models
    static func filterOpenAIModels(_ models: [String]) -> [String] {
        let desiredShapeRegexPattern = "^(gpt-(?:(?:[0-9]+(?:\\.[0-9]+)?)(?:o)?|[0-9]+\\.[0-9]+-preview)|o[0-9]+(?:-mini)?)$"
        guard let desiredShapeRegex = try? NSRegularExpression(pattern: desiredShapeRegexPattern) else {
            print("Error: Invalid regex for desired OpenAI model shapes.")
            return models.sorted()
        }
        let undesiredSubstrings = [
            "embedding", "whisper", "dall-e", "text-moderation", "babbage", "davinci",
            "curie", "ada", "gemma", "playground", "codex", "computer-use", "omni-moderation"
        ]
        let excludedModels = Set(["o1", "o1-mini"])
        var finalModelSet = Set<String>()
        for modelName in models {
            let lowercasedModelName = modelName.lowercased()
            var skip = false
            for undesired in undesiredSubstrings {
                if lowercasedModelName.contains(undesired) { skip = true; break }
            }
            if skip { continue }
            let canonicalName = getCanonicalOpenAIModelName(lowercasedModelName)
            if desiredShapeRegex.firstMatch(in: canonicalName, options: [], range: NSRange(canonicalName.startIndex..., in: canonicalName)) != nil {
                if !excludedModels.contains(canonicalName) {
                    finalModelSet.insert(canonicalName)
                }
            }
        }
        print("📋 Filtered \(models.count) OpenAI models down to \(finalModelSet.count) base models: \(finalModelSet.sorted().joined(separator: ", "))")
        return finalModelSet.sorted()
    }

    // Original getBaseModelName, exactlyMatchesBaseModel, isBaseModel (might be used by other filters or could be deprecated if all filters adopt canonical naming)
    private static func exactlyMatchesBaseModel(_ modelId: String) -> Bool {
        let baseModels = [
            "gpt-4", "gpt-4o", "gpt-3.5-turbo", "gpt-4-turbo", "gpt-4.5-turbo",
            "o1", "o1-mini", "o1-preview", "o3", "o3-mini", "o3-nano", "o4-mini"
        ]
        return baseModels.contains(modelId.lowercased())
    }
    private static func isBaseModel(_ modelName: String) -> Bool {
        let baseModels = ["gpt-4", "gpt-4o", "gpt-3.5-turbo", "o1", "o3", "o3-mini", "o3-nano", "o4-mini"]
        return baseModels.contains(modelName.lowercased())
    }
    private static func getBaseModelName(_ modelName: String) -> String {
        let lowercased = modelName.lowercased()
        if lowercased.starts(with: "gpt-4.5-preview") {
            if let dateRegex = try? NSRegularExpression(pattern: "-(?:20\\d{2}-\\d{2}-\\d{2}|\\d{6}|\\d{4})$") {
                let nameWithoutDate = dateRegex.stringByReplacingMatches(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased), withTemplate: "")
                if nameWithoutDate == "gpt-4.5-preview" { return "gpt-4.5-preview" }
            }
        }
        if lowercased.starts(with: "o4-mini") {
            if let dateRegex = try? NSRegularExpression(pattern: "-(?:20\\d{2}-\\d{2}-\\d{2}|\\d{6}|\\d{4})$") {
                let nameWithoutDate = dateRegex.stringByReplacingMatches(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased), withTemplate: "")
                if nameWithoutDate == "o4-mini" { return "o4-mini" }
            }
        }
        if let dateRange = lowercased.range(of: "-20[0-9]{2}-[0-9]{2}-[0-9]{2}", options: .regularExpression) {
            var base = String(lowercased[..<dateRange.lowerBound])
            if base == "gpt-4.5-preview" { return base }
            if (try? NSRegularExpression(pattern: "^o[0-9]+-mini$").firstMatch(in: base, options: [], range: NSRange(base.startIndex..., in: base))) != nil { return base }
            let suffixes = ["-preview", "-latest", "-turbo", "-vision", "-mini", "-realtime", "-audio", "-search", "-tts"]
            for suffix in suffixes {
                if base.hasSuffix(suffix) {
                    if suffix == "-preview" && base == "gpt-4.5-preview" { continue }
                    if suffix == "-mini" && (try? NSRegularExpression(pattern: "^o[0-9]+-mini$").firstMatch(in: base, options: [], range: NSRange(base.startIndex..., in: base))) != nil { continue }
                    base = String(base.dropLast(suffix.count))
                }
            }
            return base
        }
        var result = lowercased
        let suffixes = ["-preview", "-latest", "-turbo", "-vision", "-mini", "-realtime", "-audio", "-search", "-tts"]
        for suffix in suffixes {
            if result.hasSuffix(suffix) {
                if suffix == "-preview" && result == "gpt-4.5-preview" { continue }
                if suffix == "-mini" && (try? NSRegularExpression(pattern: "^o[0-9]+-mini$").firstMatch(in: result, options: [], range: NSRange(result.startIndex..., in: result))) != nil { continue }
                result = String(result.dropLast(suffix.count))
            }
        }
        return result
    }

    /// Filters Claude models
    static func filterClaudeModels(_ models: [String]) -> [String] {
        print("Filtering Claude models...")
        let keyModels = [
            "claude-3-opus": 100, "claude-3-5-sonnet": 95, "claude-3-sonnet": 90,
            "claude-3-haiku": 85, "claude-3-7-sonnet": 97, "claude-3-5-haiku": 87
        ]
        let familyPattern = "claude-([0-9]+(\\.[0-9]+)?)(-(opus|sonnet|haiku))?"
        var families: [String: [String]] = [:]
        for model in models {
            let id = model.lowercased()
            guard id.contains("claude") else { continue }
            var family = "claude-other"
            if let regex = try? NSRegularExpression(pattern: familyPattern),
               let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) {
                if let mainRange = Range(match.range, in: id) { family = String(id[mainRange]) }
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
            print("⚠️ No Claude models found at all, using defaults")
            return ["claude-3-opus-20240229", "claude-3-sonnet-20240229",
                    "claude-3-haiku-20240307", "claude-3-5-sonnet-20240620"]
        }
        print("📋 Filtered \(models.count) Claude models down to \(result.count) models")
        return result.sorted()
    }

    /// Filters Grok models to include only those we want to show in the picker.
    /// It prioritizes exact matches to desired identifiers and can use variants if exact matches aren't available.
    /// Vision models are excluded from the picker.
    /// - Parameter models: The complete list of models from the API
    /// - Returns: A filtered and sorted list of Grok model IDs for the picker
    static func filterGrokModels(_ models: [String]) -> [String] {
        print("Filtering Grok models with targeted strategy...")

        // These are the *ideal* identifiers we want to show in the picker.
        // The order here defines preference if multiple API models could represent the same desired identifier.
        let desiredPickerIdentifiers: [String] = [
            "grok-3-mini-fast", // Most specific variant of grok-3-mini
            "grok-3-mini",      // Base mini version of grok-3
            "grok-3",           // Base grok-3
            "grok-2",           // Base grok-2
            "grok-1.5",         // Base grok-1.5
            "grok-1"            // Base grok-1
        ]
        let desiredPickerSet = Set(desiredPickerIdentifiers)

        // This will map a desired identifier (e.g., "grok-2") to the
        // actual API model string (original casing) that will represent it (e.g., "grok-2" or "grok-2-1212").
        var representativeModels = [String: String]() // [DesiredIdentifier: ActualAPIModelID]

        // First pass: Populate with exact matches from the API list.
        // This ensures that if "grok-2" exists, it's preferred over "grok-2-1212" for the "grok-2" slot.
        for modelIDOriginalCase in models {
            let modelIDLower = modelIDOriginalCase.lowercased()
            if desiredPickerSet.contains(modelIDLower) {
                // If we haven't stored this exact model yet, or if the one stored is somehow longer (less canonical, though unlikely for exact matches)
                if representativeModels[modelIDLower] == nil || modelIDLower.count < representativeModels[modelIDLower]!.lowercased().count {
                    representativeModels[modelIDLower] = modelIDOriginalCase
                }
            }
        }

        // Second pass: For desired identifiers not yet found by an exact match,
        // try to find the best available variant from the API.
        for modelIDOriginalCase in models {
            let modelIDLower = modelIDOriginalCase.lowercased()

            // Skip vision models for the picker, and other general skips
            if modelIDLower.contains("-vision") || modelIDLower.contains("deprecated") || modelIDLower.contains("test") {
                continue
            }

            // Iterate through desired identifiers to see if this API model is a variant
            for desiredID in desiredPickerIdentifiers {
                // If we already have an exact match for this desiredID, we don't need to look for variants.
                if let existingRep = representativeModels[desiredID], existingRep.lowercased() == desiredID {
                    continue
                }

                // Check if the current API model starts with a desiredID (e.g., "grok-2-1212" starts with "grok-2")
                // and we haven't found an exact match for `desiredID` yet.
                if modelIDLower.starts(with: desiredID) {
                    // This API model is a variant of `desiredID`.
                    let currentRepresentativeForDesired = representativeModels[desiredID]

                    if currentRepresentativeForDesired == nil {
                        // No representative yet for this `desiredID`, so take this variant.
                        representativeModels[desiredID] = modelIDOriginalCase
                    } else {
                        // We have a variant, see if this new one is better (e.g., shorter, or more preferred if we add more rules)
                        // Prefer shorter variants if both are non-exact.
                        if modelIDLower.count < currentRepresentativeForDesired!.lowercased().count {
                            representativeModels[desiredID] = modelIDOriginalCase
                        }
                        // Add more complex preference logic here if needed (e.g. comparing numeric suffixes like -1212 vs -1111)
                    }
                }
            }
        }

        // Collect the actual API model IDs we've selected, using the order of desiredPickerIdentifiers for sorting.
        let finalPickerModels = desiredPickerIdentifiers.compactMap { representativeModels[$0] }

        print("📋 Filtered \(models.count) Grok models down to \(finalPickerModels.count) models for picker: \(finalPickerModels.joined(separator: ", "))")
        // The finalPickerModels will be implicitly sorted by the order of desiredPickerIdentifiers.
        // If an explicit alphabetical sort is preferred for the final list, add .sorted() here.
        var final = finalPickerModels

        // MARK: – Ensure that the key reasoning models always appear
        // In some situations the Grok models endpoint omits particular variants even though they are
        // valid for inference.  We always want the reasoning-optimised models “grok-3-mini” and
        // “grok-3-mini-fast” to be selectable.  If they weren’t returned by the API (and therefore
        // not captured as a representative model above) we append the canonical identifier so that
        // it is still offered in the picker.
        let mustHave = ["grok-3-mini-fast", "grok-3-mini"]
        for id in mustHave where !final.contains(where: { $0.lowercased().hasPrefix(id) }) {
            final.append(id)
        }

        return final
    }

    // Helper for Grok, might not be needed with the new targeted filterGrokModels strategy
    private static func extractGrokFamily(_ modelId: String) -> String {
        let id = modelId.lowercased()
        let patterns = [
            "^(grok-[0-9]+(?:\\.[0-9]+)?-mini-fast)": "$1",
            "^(grok-[0-9]+(?:\\.[0-9]+)?-mini)": "$1",
            "^(grok-[0-9]+(?:\\.[0-9]+)?-vision)": "$1",
            "^(grok-[0-9]+(?:\\.[0-9]+)?)": "$1"
        ]
        for (pattern, template) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) {
                if template == "$1" { // If template is just the first capture group
                    if let range = Range(match.range(at: 1), in: id) { return String(id[range]) }
                }
                // More complex template replacement if needed in future
            }
        }
        if id.contains("-lite") { return id.replacingOccurrences(of: "-lite", with: "") + "-lite" }
        return "grok-other"
    }

    // Helper for Grok, might not be needed
    private static func containsDateOrSuffix(_ modelName: String) -> Bool {
        let suffixes = ["-vision", "-image", "-mini", "-fast", "-1212", "-2023", "-2024", "-2025"] // -1212 is example
        let id = modelName.lowercased()
        for suffix in suffixes { if id.contains(suffix) { return true } }
        let datePattern = "\\d{4}-\\d{2}-\\d{2}" // YYYY-MM-DD
        if id.range(of: datePattern, options: .regularExpression) != nil { return true }
        let shortDatePattern = "\\d{4}$" // like -1212, assuming it's a year or version, not month-day
        if id.range(of: shortDatePattern, options: .regularExpression) != nil && id.last!.isNumber && id.dropLast().last == "-" { return true}

        return false
    }

    /// Filters Gemini models
    static func filterGeminiModels(_ models: [String]) -> [String] {
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
            let family = extractGeminiFamily(id)
            if families[family] == nil { families[family] = [] }
            families[family]?.append(model)
        }
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
            print("⚠️ No Gemini models matched our filters, using defaults")
            return ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-pro"]
        }
        print("📋 Filtered \(models.count) Gemini models down to \(result.count) models")
        return result.sorted()
    }

    // Helper for Gemini
    private static func extractGeminiFamily(_ modelId: String) -> String {
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

    // MARK: - Advanced Model Filtering (Delegates)
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

