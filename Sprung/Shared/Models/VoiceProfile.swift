//
//  VoiceProfile.swift
//  Sprung
//
//  Extracted voice characteristics for objective/narrative generation.
//  Produced by VoiceProfileService, persisted on the `.voicePrimer` CoverRef
//  (the single source of voice truth), and rendered into every voice-aware
//  prompt via `characteristicPairs` (cover letters, revision workspace, SGM).
//

import Foundation

// MARK: - Voice Profile

/// Extracted voice characteristics for objective/narrative generation
struct VoiceProfile: Codable, Equatable {
    var enthusiasm: EnthusiasmLevel
    var useFirstPerson: Bool
    var connectiveStyle: String         // "causal", "sequential", "contrastive"
    var aspirationalPhrases: [String]   // "What excites me...", "I want to build..."
    var avoidPhrases: [String]          // "leverage", "utilize", "synergy"
    var sampleExcerpts: [String]        // Verbatim voice samples
    // Extended stylistic analysis. Optional so profiles stored before these
    // fields existed still decode.
    var vocabularyRegister: String?     // Dominant mix of Anglo-Saxon / Latinate / Greek-derived lexis
    var registerModulation: String?     // When and how the author shifts between registers
    var voiceSummary: String?           // Stylist's portrait: what makes the voice recognizable, how to imitate it
    var sentenceRhythm: String?         // Length variation, clause structure, punctuation habits, cadence
    var rhetoricalMoves: [String]?      // Named recurring moves with mini-examples
    var openingStyle: String?           // How pieces open
    var closingStyle: String?           // How pieces close
}

extension VoiceProfile {
    /// Labeled characteristic pairs — the single source of truth for every
    /// "voice characteristics" prompt block (cover letters, revision
    /// workspace, SGM). Empty/absent fields are omitted.
    var characteristicPairs: [(label: String, value: String)] {
        var pairs: [(String, String)] = []
        if let summary = voiceSummary, !summary.isEmpty {
            pairs.append(("Voice Summary", summary))
        }
        pairs += [
            ("Enthusiasm", enthusiasm.displayName),
            ("Person", useFirstPerson ? "First person (I built, I discovered)" : "Third person"),
            ("Connective Style", connectiveStyle)
        ]
        if let register = vocabularyRegister, !register.isEmpty {
            pairs.append(("Vocabulary Register", register))
        }
        if let modulation = registerModulation, !modulation.isEmpty {
            pairs.append(("Register Modulation", modulation))
        }
        if let rhythm = sentenceRhythm, !rhythm.isEmpty {
            pairs.append(("Sentence Rhythm", rhythm))
        }
        if let moves = rhetoricalMoves, !moves.isEmpty {
            pairs.append(("Rhetorical Moves", moves.joined(separator: " • ")))
        }
        if let opening = openingStyle, !opening.isEmpty {
            pairs.append(("Openings", opening))
        }
        if let closing = closingStyle, !closing.isEmpty {
            pairs.append(("Closings", closing))
        }
        if !aspirationalPhrases.isEmpty {
            pairs.append(("Aspirational Phrases", aspirationalPhrases.joined(separator: ", ")))
        }
        if !avoidPhrases.isEmpty {
            pairs.append(("Never Use", avoidPhrases.joined(separator: ", ")))
        }
        return pairs
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
