//
//  CoverLetterVoiceContext.swift
//  Sprung
//
//  Builds the voice & style block for cover letter prompts from the writing
//  samples actually selected for a letter, plus the stored voice primer
//  analysis. The samples used are exactly the refs the user selected in the
//  Generate sheet (persisted on the letter as enabledRefs) — no global
//  enabledByDefault filter and no arbitrary sample cap — with deterministic
//  name ordering.
//

import Foundation
import SwiftyJSON

enum CoverLetterVoiceContext {
    /// Builds a prompt-ready voice context block.
    /// - Parameters:
    ///   - selectedRefs: The cover refs selected for the letter (only writing samples are used).
    ///   - allRefs: All stored cover refs; used to locate the voice primer analysis.
    /// - Returns: A markdown block, or an empty string when no voice data exists.
    @MainActor
    static func build(selectedRefs: [CoverRef], allRefs: [CoverRef]) -> String {
        let samples = selectedRefs
            .filter { $0.type == .writingSample && !$0.content.isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let primerRef = allRefs.first { $0.type == .voicePrimer }

        guard primerRef != nil || !samples.isEmpty else { return "" }

        var lines = ["## Voice & Style Reference"]

        // Include structured voice primer analysis if available
        if let primer = primerRef, let analysis = primer.voicePrimer {
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

        // Include the full text of every selected writing sample for voice matching
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
}
