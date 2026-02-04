//
//  CoverRefStore.swift
//  Sprung
//
//
import Foundation
import SwiftData
import SwiftyJSON

@Observable
@MainActor
final class CoverRefStore: SwiftDataStore {
    unowned let modelContext: ModelContext
    var storedCoverRefs: [CoverRef] {
        (try? modelContext.fetch(FetchDescriptor<CoverRef>())) ?? []
    }
    var defaultSources: [CoverRef] {
        storedCoverRefs.filter { $0.enabledByDefault }
    }
    init(context: ModelContext) {
        modelContext = context
        // No JSON import – SwiftData is the single source of truth.
    }
    @discardableResult
    func addCoverRef(_ coverRef: CoverRef) -> CoverRef {
        modelContext.insert(coverRef)
        saveContext()
        return coverRef
    }
    func deleteCoverRef(_ coverRef: CoverRef) {
        modelContext.delete(coverRef)
        saveContext()
    }

    // MARK: - Writer's Voice (Single Source of Truth)

    /// Canonical voice context string for all LLM prompts.
    /// Combines voice primer analysis (if available) and writing samples into a single
    /// prompt-ready block. Callers skip injection when this returns empty string.
    var writersVoice: String {
        let allRefs = storedCoverRefs
        let voicePrimerRef = allRefs.first { $0.type == .voicePrimer }
        let samples = allRefs
            .filter { $0.type == .writingSample && $0.enabledByDefault }
            .prefix(3)

        guard voicePrimerRef != nil || !samples.isEmpty else { return "" }

        var lines = ["## Voice & Style Reference"]

        // Include structured voice primer analysis if available
        if let primer = voicePrimerRef, let analysis = primer.voicePrimer {
            lines.append("""

            ### Analyzed Voice Characteristics

            The following voice profile was extracted from the candidate's writing samples.
            Generated content MUST match these characteristics.
            """)

            if let tone = analysis["tone"]["description"].string, !tone.isEmpty {
                lines.append("**Tone:** \(tone)")
            }
            if let structure = analysis["structure"]["description"].string, !structure.isEmpty {
                lines.append("**Sentence Structure:** \(structure)")
            }
            if let vocab = analysis["vocabulary"]["description"].string, !vocab.isEmpty {
                lines.append("**Vocabulary:** \(vocab)")
            }
            if let rhetoric = analysis["rhetoric"]["description"].string, !rhetoric.isEmpty {
                lines.append("**Rhetoric Style:** \(rhetoric)")
            }

            let strengths = analysis["markers"]["strengths"].arrayValue.compactMap { $0.string }
            if !strengths.isEmpty {
                lines.append("**Writing Strengths:** \(strengths.joined(separator: ", "))")
            }

            let quirks = analysis["markers"]["quirks"].arrayValue.compactMap { $0.string }
            if !quirks.isEmpty {
                lines.append("**Distinctive Traits:** \(quirks.joined(separator: ", "))")
            }

            let recommendations = analysis["markers"]["recommendations"].arrayValue.compactMap { $0.string }
            if !recommendations.isEmpty {
                lines.append("**Style Notes:** \(recommendations.joined(separator: "; "))")
            }
        }

        // Include actual writing sample text for voice matching
        if !samples.isEmpty {
            lines.append("""

            ### Writing Samples (Full Text)

            The following are actual writing samples from this candidate.
            Study these carefully and match their:
            - Vocabulary choices and technical terminology
            - Sentence length and structure patterns
            - Level of formality
            - How they describe technical work
            - How they frame achievements (narrative vs. metric-focused)
            """)

            for (index, sample) in samples.enumerated() {
                lines.append("")
                lines.append("#### Sample \(index + 1): \(sample.name)")
                lines.append("")
                lines.append(sample.content)
            }
        }

        return lines.joined(separator: "\n")
    }

    // No JSON File backing – SwiftData only.
    // `saveContext()` now lives in `SwiftDataStore`.
}
