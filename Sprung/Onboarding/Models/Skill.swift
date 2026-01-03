//
//  Skill.swift
//  Sprung
//
//  Skill model for comprehensive ATS-optimized skill tracking.
//  Each skill includes evidence, proficiency, and ATS variants.
//

import Foundation

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
}

/// Proficiency level for a skill
enum Proficiency: String, Codable {
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

/// How strongly the evidence demonstrates the skill
enum EvidenceStrength: String, Codable {
    case primary     // Deep demonstration in source
    case supporting  // Significant use shown
    case mention     // Referenced but not demonstrated
}

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

/// A single skill with evidence and ATS variants
struct Skill: Codable, Identifiable, Equatable {
    let id: UUID
    let canonical: String           // "Python" (display name)
    let atsVariants: [String]       // ["python", "Python 3", "python3", "Python programming"]
    let category: SkillCategory
    let proficiency: Proficiency
    let evidence: [SkillEvidence]
    let relatedSkills: [UUID]       // Links to related skills
    let lastUsed: String?           // "2024" or "present"

    enum CodingKeys: String, CodingKey {
        case id, canonical
        case atsVariants = "ats_variants"
        case category, proficiency, evidence
        case relatedSkills = "related_skills"
        case lastUsed = "last_used"
    }

    /// Custom decoder to handle LLM responses
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle id as UUID or String
        if let uuidString = try? container.decode(String.self, forKey: .id) {
            self.id = UUID(uuidString: uuidString) ?? UUID()
        } else {
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        }

        self.canonical = try container.decode(String.self, forKey: .canonical)
        self.atsVariants = try container.decodeIfPresent([String].self, forKey: .atsVariants) ?? []
        self.category = try container.decode(SkillCategory.self, forKey: .category)
        self.proficiency = try container.decode(Proficiency.self, forKey: .proficiency)
        self.evidence = try container.decodeIfPresent([SkillEvidence].self, forKey: .evidence) ?? []

        // Handle relatedSkills as array of UUIDs or strings
        if let uuidStrings = try? container.decode([String].self, forKey: .relatedSkills) {
            self.relatedSkills = uuidStrings.compactMap { UUID(uuidString: $0) }
        } else {
            self.relatedSkills = try container.decodeIfPresent([UUID].self, forKey: .relatedSkills) ?? []
        }

        self.lastUsed = try container.decodeIfPresent(String.self, forKey: .lastUsed)
    }

    /// Memberwise initializer
    init(
        id: UUID = UUID(),
        canonical: String,
        atsVariants: [String],
        category: SkillCategory,
        proficiency: Proficiency,
        evidence: [SkillEvidence],
        relatedSkills: [UUID] = [],
        lastUsed: String? = nil
    ) {
        self.id = id
        self.canonical = canonical
        self.atsVariants = atsVariants
        self.category = category
        self.proficiency = proficiency
        self.evidence = evidence
        self.relatedSkills = relatedSkills
        self.lastUsed = lastUsed
    }
}
