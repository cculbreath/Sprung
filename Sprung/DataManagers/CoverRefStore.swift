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

    /// Canonical writer's-voice sample selection: enabled-by-default writing
    /// samples, capped at 3. Static so callers that already hold a CoverRef
    /// array (e.g. the revision workspace export) share the exact criteria
    /// `writersVoice` uses.
    static func voiceSamples(in coverRefs: [CoverRef]) -> [CoverRef] {
        Array(
            coverRefs
                .filter { $0.type == .writingSample && $0.enabledByDefault }
                .prefix(3)
        )
    }

    /// Short stylist's portrait of the candidate's voice from the analyzed
    /// voice primer, suitable for inline "voice cue" prompt blocks.
    var voiceSummary: String? {
        storedCoverRefs
            .first { $0.type == .voicePrimer }?
            .voiceProfile?
            .voiceSummary
    }

    /// Canonical voice context string for all LLM prompts.
    /// Combines voice primer analysis (if available) and writing samples into a single
    /// prompt-ready block. Callers skip injection when this returns empty string.
    var writersVoice: String {
        let allRefs = storedCoverRefs
        let voicePrimerRef = allRefs.first { $0.type == .voicePrimer }
        let samples = Self.voiceSamples(in: allRefs)

        guard voicePrimerRef != nil || !samples.isEmpty else { return "" }

        var lines = ["## Voice & Style Reference"]

        // Include the analyzed voice profile if available
        if let profile = voicePrimerRef?.voiceProfile {
            lines.append("""

            ### Analyzed Voice Characteristics

            The following voice profile was extracted from the candidate's writing samples.
            Generated content MUST match these characteristics.
            """)

            for (label, value) in profile.characteristicPairs {
                lines.append("**\(label):** \(value)")
            }
            if !profile.sampleExcerpts.isEmpty {
                lines.append("**Voice Excerpts:** " + profile.sampleExcerpts.map { "\"\($0)\"" }.joined(separator: " | "))
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
