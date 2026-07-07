//
//  TitleSetTypes.swift
//  Sprung
//
//  Title-set value types used by Seed Generation (TitleOptionsGenerator),
//  the revision agent, and the onboarding title-set flow. Stored as JSON in
//  TitleSetRecord and threaded through generation/export prompts.
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
