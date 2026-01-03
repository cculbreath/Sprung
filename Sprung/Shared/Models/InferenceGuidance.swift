//
//  InferenceGuidance.swift
//  Sprung
//
//  Node-specific inference guidance, injected at resume customization time.
//  Provides a general-purpose mechanism for attaching prompting instructions
//  to resume tree nodes without special-casing individual fields.
//

import Foundation
import SwiftData

/// Source of guidance: auto-generated or user-edited
enum GuidanceSource: String, Codable {
    case auto   // Generated during onboarding
    case user   // Manually created or edited
}

/// Node-specific inference guidance, injected at resume customization time
@Model
final class InferenceGuidance {
    @Attribute(.unique) var id: UUID = UUID()

    /// Tree node key this guidance applies to
    /// Examples: "custom.jobTitles", "objective", "skills", "experience.*.bullets"
    var nodeKey: String

    /// Human-readable name for UI
    var displayName: String

    /// Prompt text injected during customization
    /// Can reference {ATTACHMENTS} placeholder for structured data
    var prompt: String

    /// Structured data as JSON string (TitleSet[], VoiceProfile, etc.)
    var attachmentsJSON: String?

    /// Source: auto-generated or user-edited
    private var _source: String = GuidanceSource.auto.rawValue

    var source: GuidanceSource {
        get { GuidanceSource(rawValue: _source) ?? .auto }
        set { _source = newValue.rawValue }
    }

    /// When created/updated
    var updatedAt: Date = Date()

    /// Whether this guidance is active (can be disabled without deleting)
    var isEnabled: Bool = true

    init(
        id: UUID = UUID(),
        nodeKey: String,
        displayName: String,
        prompt: String,
        attachmentsJSON: String? = nil,
        source: GuidanceSource = .auto,
        updatedAt: Date = Date(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.nodeKey = nodeKey
        self.displayName = displayName
        self.prompt = prompt
        self.attachmentsJSON = attachmentsJSON
        self._source = source.rawValue
        self.updatedAt = updatedAt
        self.isEnabled = isEnabled
    }

    /// Render prompt with attachments substituted
    func renderedPrompt() -> String {
        guard let json = attachmentsJSON else { return prompt }
        return prompt.replacingOccurrences(of: "{ATTACHMENTS}", with: json)
    }
}
