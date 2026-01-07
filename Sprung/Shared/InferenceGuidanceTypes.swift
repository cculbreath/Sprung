//
//  InferenceGuidanceTypes.swift
//  Sprung
//
//  Supporting types for inference guidance attachments.
//  These types are stored as JSON in InferenceGuidance.attachmentsJSON.
//

import Foundation

// MARK: - Title Sets

/// Pre-validated 4-title combination
struct TitleSet: Codable, Identifiable, Equatable {
    let id: String
    var titles: [String]          // Exactly 4
    var emphasis: TitleEmphasis
    var suggestedFor: [String]    // Job types: ["R&D", "software", "academic"]
    var isFavorite: Bool

    init(
        id: String = UUID().uuidString,
        titles: [String],
        emphasis: TitleEmphasis = .balanced,
        suggestedFor: [String] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.titles = titles
        self.emphasis = emphasis
        self.suggestedFor = suggestedFor
        self.isFavorite = isFavorite
    }

    /// Display string: "Physicist. Developer. Educator. Machinist."
    var displayString: String {
        titles.joined(separator: ". ") + "."
    }

    // Custom decoder to handle optional fields with defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        titles = try container.decode([String].self, forKey: .titles)
        emphasis = try container.decode(TitleEmphasis.self, forKey: .emphasis)
        suggestedFor = try container.decodeIfPresent([String].self, forKey: .suggestedFor) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

enum TitleEmphasis: String, Codable, CaseIterable {
    case technical
    case research
    case leadership
    case balanced

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Identity Vocabulary

/// Identity vocabulary term extracted from documents
struct IdentityTerm: Codable, Identifiable, Equatable {
    let id: String
    var term: String              // "Physicist", "Developer"
    var evidenceStrength: Double  // 0-1
    var sourceDocumentIds: [String]

    init(
        id: String = UUID().uuidString,
        term: String,
        evidenceStrength: Double = 0.5,
        sourceDocumentIds: [String] = []
    ) {
        self.id = id
        self.term = term
        self.evidenceStrength = evidenceStrength
        self.sourceDocumentIds = sourceDocumentIds
    }

    // Custom decoder to handle optional fields with defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        term = try container.decode(String.self, forKey: .term)
        evidenceStrength = try container.decode(Double.self, forKey: .evidenceStrength)
        sourceDocumentIds = try container.decodeIfPresent([String].self, forKey: .sourceDocumentIds) ?? []
    }
}

// MARK: - Voice Profile

/// Extracted voice characteristics for objective/narrative generation
struct VoiceProfile: Codable, Equatable {
    var enthusiasm: EnthusiasmLevel
    var useFirstPerson: Bool
    var connectiveStyle: String         // "causal", "sequential", "contrastive"
    var aspirationalPhrases: [String]   // "What excites me...", "I want to build..."
    var avoidPhrases: [String]          // "leverage", "utilize", "synergy"
    var sampleExcerpts: [String]        // Verbatim voice samples

    init(
        enthusiasm: EnthusiasmLevel = .moderate,
        useFirstPerson: Bool = true,
        connectiveStyle: String = "causal",
        aspirationalPhrases: [String] = [],
        avoidPhrases: [String] = [],
        sampleExcerpts: [String] = []
    ) {
        self.enthusiasm = enthusiasm
        self.useFirstPerson = useFirstPerson
        self.connectiveStyle = connectiveStyle
        self.aspirationalPhrases = aspirationalPhrases
        self.avoidPhrases = avoidPhrases
        self.sampleExcerpts = sampleExcerpts
    }
}

enum EnthusiasmLevel: String, Codable, CaseIterable {
    case measured   // "I'm interested in..."
    case moderate   // "I'm drawn to...", "What appeals to me..."
    case high       // "I'm excited by...", "I love..."

    var displayName: String {
        switch self {
        case .measured: return "Measured"
        case .moderate: return "Moderate"
        case .high: return "Enthusiastic"
        }
    }

    var examplePhrases: [String] {
        switch self {
        case .measured: return ["I'm interested in", "I find value in", "I appreciate"]
        case .moderate: return ["I'm drawn to", "What appeals to me", "I enjoy"]
        case .high: return ["I'm excited by", "I love", "I'm passionate about"]
        }
    }
}

// MARK: - Attachment Container

/// Container for structured attachments stored in InferenceGuidance.attachmentsJSON
struct GuidanceAttachments: Codable {
    var titleSets: [TitleSet]?
    var vocabulary: [IdentityTerm]?
    var voiceProfile: VoiceProfile?

    init(
        titleSets: [TitleSet]? = nil,
        vocabulary: [IdentityTerm]? = nil,
        voiceProfile: VoiceProfile? = nil
    ) {
        self.titleSets = titleSets
        self.vocabulary = vocabulary
        self.voiceProfile = voiceProfile
    }

    func asJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func from(json: String?) -> GuidanceAttachments? {
        guard let json = json, let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(GuidanceAttachments.self, from: data)
    }

    enum CodingKeys: String, CodingKey {
        case titleSets = "title_sets"
        case vocabulary
        case voiceProfile = "voice_profile"
    }
}
