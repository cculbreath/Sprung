//
//  ModelPricing.swift
//  Sprung
//
//  Live model pricing sourced from the OpenRouter models endpoint, which
//  publishes per-token USD prices (including cache read/write rates) for
//  Anthropic-vendor models alongside everything else. Used by the onboarding
//  budget sheet for pre-run cost estimates and by the debug token summary for
//  a cost-so-far readout.
//
//  No prices are hardcoded: the table is built from a live fetch and persisted
//  with its fetch date. When OpenRouter omits explicit cache rates, they are
//  derived from Anthropic's published pricing STRUCTURE (cache writes 1.25x
//  input, reads 0.1x input) — multipliers, never absolute dollar amounts.
//
//  ID normalization bridges the two naming schemes:
//    Anthropic direct:  "claude-sonnet-4-6", "claude-haiku-4-5-20251001"
//    OpenRouter slug:   "anthropic/claude-sonnet-4.6"
//

import Foundation

/// USD per million tokens for one model.
struct ModelPrice: Codable, Hashable {
    let inputPerMTok: Double
    let outputPerMTok: Double
    let cacheReadPerMTok: Double
    let cacheWritePerMTok: Double
}

enum ModelPricing {
    /// Anthropic cache pricing structure relative to base input price.
    /// Used only when OpenRouter omits explicit cache rates for a model.
    static let cacheReadMultiplier = 0.1
    static let cacheWriteMultiplier = 1.25

    private static let tableDefaultsKey = "modelPricingTableJSON"
    private static let tableDateDefaultsKey = "modelPricingTableDate"

    // MARK: - ID Normalization

    /// Canonical form for matching model IDs across naming schemes:
    /// lowercase, vendor prefix and ":variant" suffix stripped, dots → dashes,
    /// trailing -YYYYMMDD snapshot date stripped.
    static func normalize(_ modelId: String) -> String {
        var id = modelId.lowercased()
        if let slash = id.firstIndex(of: "/") {
            id = String(id[id.index(after: slash)...])
        }
        if let colon = id.firstIndex(of: ":") {
            id = String(id[..<colon])
        }
        id = id.replacingOccurrences(of: ".", with: "-")
        id = id.replacingOccurrences(
            of: #"-20\d{6}$"#,
            with: "",
            options: .regularExpression
        )
        return id
    }

    /// Parse a normalized ID into its Claude family token and version vector
    /// (every integer group, in order). Works for both historical orderings:
    /// "claude-3-5-haiku" → (haiku, [3, 5]) and "claude-opus-4-8" → (opus, [4, 8]).
    static func familyAndVersion(_ normalizedId: String) -> (family: String, version: [Int])? {
        let families = ["opus", "sonnet", "haiku"]
        guard let family = families.first(where: { normalizedId.contains($0) }) else { return nil }
        let version = normalizedId
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        return (family, version)
    }

    /// Lexicographic version-vector comparison; longer wins after equal prefix
    /// (so a dated snapshot outranks its undated alias of the same version).
    static func isVersion(_ lhs: [Int], newerThan rhs: [Int]) -> Bool {
        for (l, r) in zip(lhs, rhs) where l != r {
            return l > r
        }
        return lhs.count > rhs.count
    }

    // MARK: - Table Construction

    /// Build a normalized-key price table from a fetched OpenRouter model list.
    static func buildTable(from models: [OpenRouterModel]) -> [String: ModelPrice] {
        var table: [String: ModelPrice] = [:]
        for model in models {
            guard let pricing = model.pricing,
                  let promptPerToken = pricing.promptUSDPerToken,
                  let completionPerToken = pricing.completionUSDPerToken,
                  promptPerToken > 0 || completionPerToken > 0 else { continue }
            // Skip ":variant" endpoints (":free", ":thinking", …) — their pricing
            // does not represent the canonical model.
            if model.id.contains(":") { continue }

            let inputPerMTok = promptPerToken * 1_000_000
            let outputPerMTok = completionPerToken * 1_000_000
            let cacheRead = pricing.cacheReadUSDPerToken.map { $0 * 1_000_000 }
                ?? inputPerMTok * cacheReadMultiplier
            let cacheWrite = pricing.cacheWriteUSDPerToken.map { $0 * 1_000_000 }
                ?? inputPerMTok * cacheWriteMultiplier
            let price = ModelPrice(
                inputPerMTok: inputPerMTok,
                outputPerMTok: outputPerMTok,
                cacheReadPerMTok: cacheRead,
                cacheWritePerMTok: cacheWrite
            )
            // Keyed by raw id (exact OpenRouter lookups) and normalized id
            // (Anthropic-direct lookups). First write wins on collisions so the
            // canonical listing beats any later variant.
            if table[model.id] == nil { table[model.id] = price }
            let normalized = normalize(model.id)
            if table[normalized] == nil { table[normalized] = price }
        }
        return table
    }

    // MARK: - Lookup

    /// Price for a model ID from either naming scheme. Exact match first, then
    /// normalized, then family+version fallback (handles residual scheme drift).
    static func price(for modelId: String, in table: [String: ModelPrice]) -> ModelPrice? {
        if let exact = table[modelId] { return exact }
        let normalized = normalize(modelId)
        if let match = table[normalized] { return match }
        guard let target = familyAndVersion(normalized) else { return nil }
        for (key, value) in table {
            if let candidate = familyAndVersion(key),
               candidate.family == target.family,
               candidate.version == target.version {
                return value
            }
        }
        return nil
    }

    // MARK: - Cost

    /// Total USD for a usage breakdown at a model's rates.
    static func costUSD(
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheCreationTokens: Int,
        at price: ModelPrice
    ) -> Double {
        (Double(inputTokens) * price.inputPerMTok
            + Double(outputTokens) * price.outputPerMTok
            + Double(cacheReadTokens) * price.cacheReadPerMTok
            + Double(cacheCreationTokens) * price.cacheWritePerMTok) / 1_000_000
    }

    // MARK: - Persistence

    /// Persist a fetched table so views without fetch access (debug window)
    /// can price usage, stamped with the fetch date.
    static func persistTable(_ table: [String: ModelPrice]) {
        guard let data = try? JSONEncoder().encode(table) else { return }
        UserDefaults.standard.set(data, forKey: tableDefaultsKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: tableDateDefaultsKey)
    }

    static func loadPersistedTable() -> (table: [String: ModelPrice], asOf: Date)? {
        guard let data = UserDefaults.standard.data(forKey: tableDefaultsKey),
              let table = try? JSONDecoder().decode([String: ModelPrice].self, from: data) else {
            return nil
        }
        let timestamp = UserDefaults.standard.double(forKey: tableDateDefaultsKey)
        guard timestamp > 0 else { return nil }
        return (table, Date(timeIntervalSince1970: timestamp))
    }
}
