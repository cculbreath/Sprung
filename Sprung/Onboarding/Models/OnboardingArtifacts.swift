//
//  OnboardingArtifacts.swift
//  Sprung
//
//  Domain model for onboarding artifacts.
//
import Foundation
import SwiftyJSON

/// Definition for a custom resume field that should be generated during experience defaults creation.
/// The key uses dot notation (e.g., "custom.objective") and the description guides the LLM on what to generate.
struct CustomFieldDefinition: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    /// Field key using dot notation, e.g., "custom.objective", "custom.targetRoles"
    var key: String
    /// Description guiding the LLM on what content to generate for this field
    var description: String

    init(id: UUID = UUID(), key: String, description: String) {
        self.id = id
        self.key = key
        self.description = description
    }
}

struct OnboardingArtifacts {
    var applicantProfile: JSON?
    var skeletonTimeline: JSON?
    var enabledSections: Set<String> = []
    /// Custom field definitions configured during section toggle
    var customFieldDefinitions: [CustomFieldDefinition] = []
    var experienceCards: [JSON] = []
    var writingSamples: [JSON] = []
    var artifactRecords: [JSON] = []
    var knowledgeCards: [JSON] = []
}
