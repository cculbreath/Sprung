//
//  CoverRef+WritingSamples.swift
//  Sprung
//
//  Extension for retrieving full cover letter writing samples for prompt inclusion.
//  These samples demonstrate the candidate's authentic writing voice for LLM guidance.
//

import Foundation

extension Array where Element == CoverRef {

    /// Get full text of writing sample cover letters for prompt inclusion
    /// - Parameter maxSamples: Maximum number of samples to include (default: 3)
    /// - Returns: Formatted string containing full cover letter text
    func writingSamplesForPrompt(maxSamples: Int = 3) -> String {
        let samples = self
            .filter { $0.type == .writingSample }
            .prefix(maxSamples)

        guard !samples.isEmpty else {
            return "(No writing samples available)"
        }

        return samples.enumerated().map { index, ref in
            "--- WRITING SAMPLE \(index + 1): \(ref.name) ---\n\n\(ref.content)"
        }.joined(separator: "\n\n")
    }

    /// Get full text of writing samples with voice guidance header for resume prompts
    /// - Parameter maxSamples: Maximum samples (default: 2 for resume context)
    /// - Returns: Formatted string with guidance header
    func voiceContextForPrompt(maxSamples: Int = 2) -> String {
        let samples = writingSamplesForPrompt(maxSamples: maxSamples)

        guard samples != "(No writing samples available)" else {
            return samples
        }

        return """
        The following cover letters demonstrate the candidate's authentic writing voice.
        Match this tone, level of technical specificity, and framing approach:

        \(samples)

        VOICE GUIDANCE:
        - Match the candidate's natural communication style shown above
        - Use similar level of technical detail and specificity
        - Avoid generic corporate language not present in the samples
        - Maintain the candidate's authentic framing of their background
        """
    }
}
