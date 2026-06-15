//
//  AnthropicModel+Selectable.swift
//  Sprung
//
//  Shared predicate for user-facing Anthropic model pickers, replacing the
//  copy-pasted `claude-`/`instant` filter that lived in three views.
//

import Foundation
import SwiftOpenAI

extension AnthropicModel {
    /// Whether this model should be offered in user-facing pickers:
    /// the current Claude family, excluding deprecated `instant` variants.
    var isSelectable: Bool {
        let id = id.lowercased()
        return id.hasPrefix("claude-") && !id.contains("instant")
    }
}
