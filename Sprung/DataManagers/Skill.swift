//
//  Skill.swift
//  Sprung
//
//  SwiftData model for skills extracted during onboarding.
//  Comprehensive ATS-optimized skill tracking with evidence and proficiency.
//

import Foundation
import SwiftData

// MARK: - Skill Category

/// Category for organizing skills
enum SkillCategory: String, Codable, CaseIterable {
    case languages = "Programming Languages"
    case frameworks = "Frameworks & Libraries"
    case tools = "Tools & Platforms"
    case hardware = "Hardware & Electronics"
    case fabrication = "Fabrication & Manufacturing"
    case scientific = "Scientific & Analysis"
    case soft = "Leadership & Communication"
    case domain = "Domain Expertise"

    var icon: String {
        switch self {
        case .languages: return "chevron.left.forwardslash.chevron.right"
        case .frameworks: return "square.stack.3d.up"
        case .tools: return "wrench.and.screwdriver"
        case .hardware: return "cpu"
        case .fabrication: return "hammer"
        case .scientific: return "flask"
        case .soft: return "person.2"
        case .domain: return "building.2"
        }
    }
}

// MARK: - Proficiency Level

/// Proficiency level for a skill
enum Proficiency: String, Codable, CaseIterable {
    case expert      // Years of deep use, can teach others
    case proficient  // Regular use, comfortable independently
    case familiar    // Some experience, would need ramp-up

    var sortOrder: Int {
        switch self {
        case .expert: return 0
        case .proficient: return 1
        case .familiar: return 2
        }
    }
}

// MARK: - Evidence Strength

/// How strongly the evidence demonstrates the skill
enum EvidenceStrength: String, Codable {
    case primary     // Deep demonstration in source
    case supporting  // Significant use shown
    case mention     // Referenced but not demonstrated
}

// MARK: - Skill Evidence

/// Evidence of a skill from a specific document
struct SkillEvidence: Codable, Equatable {
    let documentId: String
    let location: String            // "Pages 45-60", "commit abc123"
    let context: String             // Brief description of how skill was used
    let strength: EvidenceStrength  // primary, supporting, mention

    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case location, context, strength
    }
}

// MARK: - Skill Model

@Model
class Skill: Identifiable, Codable {
    var id: UUID

    // MARK: - Core Fields

    /// Canonical display name (e.g., "Python")
    var canonical: String

    /// JSON-encoded array of ATS variants (e.g., ["python", "Python 3", "python3"])
    var atsVariantsJSON: String?

    /// Category for organizing skills
    var categoryRaw: String

    /// Proficiency level
    var proficiencyRaw: String

    /// JSON-encoded array of SkillEvidence
    var evidenceJSON: String?

    /// JSON-encoded array of related skill UUIDs
    var relatedSkillsJSON: String?

    /// Last year the skill was used (e.g., "2024" or "present")
    var lastUsed: String?

    // MARK: - Onboarding Metadata

    /// Indicates this was created via onboarding interview
    var isFromOnboarding: Bool = false

    /// Skills created during onboarding start as pending until user approves
    var isPending: Bool = false

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        canonical: String,
        atsVariants: [String] = [],
        category: SkillCategory,
        proficiency: Proficiency,
        evidence: [SkillEvidence] = [],
        relatedSkills: [UUID] = [],
        lastUsed: String? = nil,
        isFromOnboarding: Bool = false,
        isPending: Bool = false
    ) {
        self.id = id
        self.canonical = canonical
        self.categoryRaw = category.rawValue
        self.proficiencyRaw = proficiency.rawValue
        self.lastUsed = lastUsed
        self.isFromOnboarding = isFromOnboarding
        self.isPending = isPending

        // Encode arrays to JSON
        self.atsVariants = atsVariants
        self.evidence = evidence
        self.relatedSkills = relatedSkills
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, canonical
        case atsVariantsJSON = "ats_variants"
        case categoryRaw = "category"
        case proficiencyRaw = "proficiency"
        case evidenceJSON = "evidence"
        case relatedSkillsJSON = "related_skills"
        case lastUsed = "last_used"
        case isFromOnboarding
        case isPending
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle id as UUID or String
        if let uuidString = try? container.decode(String.self, forKey: .id) {
            self.id = UUID(uuidString: uuidString) ?? UUID()
        } else {
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        }

        self.canonical = try container.decode(String.self, forKey: .canonical)
        self.categoryRaw = try container.decode(String.self, forKey: .categoryRaw)
        self.proficiencyRaw = try container.decode(String.self, forKey: .proficiencyRaw)
        self.lastUsed = try container.decodeIfPresent(String.self, forKey: .lastUsed)
        self.isFromOnboarding = try container.decodeIfPresent(Bool.self, forKey: .isFromOnboarding) ?? false
        self.isPending = try container.decodeIfPresent(Bool.self, forKey: .isPending) ?? false

        // Decode atsVariants - handle both JSON string and direct array
        if let variantsString = try? container.decode(String.self, forKey: .atsVariantsJSON) {
            self.atsVariantsJSON = variantsString
        } else if let variants = try? container.decode([String].self, forKey: .atsVariantsJSON),
                  let data = try? JSONEncoder().encode(variants),
                  let json = String(data: data, encoding: .utf8) {
            self.atsVariantsJSON = json
        }

        // Decode evidence - handle both JSON string and direct array
        if let evidenceString = try? container.decode(String.self, forKey: .evidenceJSON) {
            self.evidenceJSON = evidenceString
        } else if let evidence = try? container.decode([SkillEvidence].self, forKey: .evidenceJSON),
                  let data = try? JSONEncoder().encode(evidence),
                  let json = String(data: data, encoding: .utf8) {
            self.evidenceJSON = json
        }

        // Decode relatedSkills - handle both JSON string and direct array
        if let relatedString = try? container.decode(String.self, forKey: .relatedSkillsJSON) {
            self.relatedSkillsJSON = relatedString
        } else if let relatedIds = try? container.decode([UUID].self, forKey: .relatedSkillsJSON),
                  let data = try? JSONEncoder().encode(relatedIds),
                  let json = String(data: data, encoding: .utf8) {
            self.relatedSkillsJSON = json
        } else if let relatedStrings = try? container.decode([String].self, forKey: .relatedSkillsJSON) {
            let uuids = relatedStrings.compactMap { UUID(uuidString: $0) }
            if let data = try? JSONEncoder().encode(uuids),
               let json = String(data: data, encoding: .utf8) {
                self.relatedSkillsJSON = json
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(canonical, forKey: .canonical)
        try container.encodeIfPresent(atsVariantsJSON, forKey: .atsVariantsJSON)
        try container.encode(categoryRaw, forKey: .categoryRaw)
        try container.encode(proficiencyRaw, forKey: .proficiencyRaw)
        try container.encodeIfPresent(evidenceJSON, forKey: .evidenceJSON)
        try container.encodeIfPresent(relatedSkillsJSON, forKey: .relatedSkillsJSON)
        try container.encodeIfPresent(lastUsed, forKey: .lastUsed)
        try container.encode(isFromOnboarding, forKey: .isFromOnboarding)
        try container.encode(isPending, forKey: .isPending)
    }

    // MARK: - Computed Properties

    /// Category as enum
    var category: SkillCategory {
        get {
            SkillCategory(rawValue: categoryRaw) ?? .domain
        }
        set {
            categoryRaw = newValue.rawValue
        }
    }

    /// Proficiency as enum
    var proficiency: Proficiency {
        get {
            Proficiency(rawValue: proficiencyRaw) ?? .familiar
        }
        set {
            proficiencyRaw = newValue.rawValue
        }
    }

    /// ATS variants for this skill
    var atsVariants: [String] {
        get {
            guard let json = atsVariantsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if newValue.isEmpty {
                atsVariantsJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                atsVariantsJSON = json
            }
        }
    }

    /// Evidence demonstrating this skill
    var evidence: [SkillEvidence] {
        get {
            guard let json = evidenceJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([SkillEvidence].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if newValue.isEmpty {
                evidenceJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                evidenceJSON = json
            }
        }
    }

    /// Related skill IDs
    var relatedSkills: [UUID] {
        get {
            guard let json = relatedSkillsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([UUID].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if newValue.isEmpty {
                relatedSkillsJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                relatedSkillsJSON = json
            }
        }
    }

    /// All name variants for ATS matching (canonical + variants)
    var allVariants: [String] {
        [canonical] + atsVariants
    }

    /// Check if this skill matches a search term
    func matches(_ term: String) -> Bool {
        let lowercased = term.lowercased()
        return allVariants.contains { $0.lowercased().contains(lowercased) }
    }
}

// MARK: - Sendable Conformance

extension Skill: @unchecked Sendable {}
