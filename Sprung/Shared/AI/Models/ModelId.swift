//
//  ModelId.swift
//  Sprung
//

import Foundation

/// A model identifier of the OpenRouter form `provider/model`
/// (e.g. `anthropic/claude-…`, `openai/gpt-…`). A bare id with no `/` has a
/// `nil` provider and is its own `strippingProvider` result.
///
/// Centralizes the provider-prefix handling that was previously hand-rolled at
/// several call sites (`hasPrefix("anthropic/")`, `hasPrefix("openai/") ? dropFirst(7)`).
struct ModelId {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// The provider segment before the first `/`, or `nil` if the id is unprefixed.
    var provider: String? {
        guard let slash = rawValue.firstIndex(of: "/") else { return nil }
        return String(rawValue[..<slash])
    }

    /// True when the model routes through Anthropic (`anthropic/…`).
    var isAnthropic: Bool { provider == "anthropic" }

    /// The id with the given `provider/` prefix removed, or the raw id unchanged
    /// if that prefix is absent. Used to hand a bare id to a provider's native
    /// API (e.g. strip `openai/` before calling OpenAI's Responses API).
    func strippingProvider(_ provider: String) -> String {
        let prefix = provider + "/"
        return rawValue.hasPrefix(prefix) ? String(rawValue.dropFirst(prefix.count)) : rawValue
    }
}
