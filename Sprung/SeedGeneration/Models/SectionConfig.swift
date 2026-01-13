//
//  SectionConfig.swift
//  Sprung
//
//  Bundled section configuration: enabled sections + custom field definitions.
//  Replaces enabledSectionsCSV with a structured JSON-based approach.
//

import Foundation

/// Bundled section configuration combining enabled sections and custom field definitions.
/// Persisted as JSON in OnboardingSession.sectionConfigJSON.
struct SectionConfig: Codable, Equatable {
    /// Set of enabled section identifiers (e.g., "work", "education", "custom.objective")
    var enabledSections: Set<String>

    /// Custom field definitions configured during section toggle
    var customFields: [CustomFieldDefinition]

    init(enabledSections: Set<String> = [], customFields: [CustomFieldDefinition] = []) {
        self.enabledSections = enabledSections
        self.customFields = customFields
    }

    // MARK: - JSON Serialization

    /// Decode from JSON string
    static func from(json: String) throws -> SectionConfig {
        guard let data = json.data(using: .utf8) else {
            throw SectionConfigError.invalidEncoding
        }
        return try JSONDecoder().decode(SectionConfig.self, from: data)
    }

    /// Encode to JSON string for persistence
    func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw SectionConfigError.invalidEncoding
        }
        return jsonString
    }

    // MARK: - Convenience Methods

    /// Check if a section is enabled
    func isEnabled(_ sectionKey: ExperienceSectionKey) -> Bool {
        enabledSections.contains(sectionKey.rawValue)
    }

    /// Check if a custom field key is enabled
    func isCustomFieldEnabled(_ key: String) -> Bool {
        enabledSections.contains(key)
    }

    /// Get custom field definition for a key
    func customField(for key: String) -> CustomFieldDefinition? {
        customFields.first { $0.key == key }
    }

    /// All enabled standard sections (non-custom)
    var enabledStandardSections: [ExperienceSectionKey] {
        ExperienceSectionKey.allCases.filter { sectionKey in
            sectionKey != .custom && enabledSections.contains(sectionKey.rawValue)
        }
    }

    /// All enabled custom field keys
    var enabledCustomFieldKeys: [String] {
        customFields
            .map(\.key)
            .filter { enabledSections.contains($0) }
    }
}

enum SectionConfigError: Error, LocalizedError {
    case invalidEncoding
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Failed to encode/decode SectionConfig JSON"
        case .decodingFailed(let error):
            return "SectionConfig decoding failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Migration Support

extension SectionConfig {
    /// Create SectionConfig from legacy enabledSectionsCSV and customFieldDefinitions
    static func from(
        enabledSectionsCSV: String?,
        customFieldDefinitions: [CustomFieldDefinition]
    ) -> SectionConfig {
        var enabledSections = Set<String>()

        if let csv = enabledSectionsCSV, !csv.isEmpty {
            enabledSections = Set(
                csv.split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
            )
        }

        return SectionConfig(
            enabledSections: enabledSections,
            customFields: customFieldDefinitions
        )
    }
}
