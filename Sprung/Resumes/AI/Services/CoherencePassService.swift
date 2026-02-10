//
//  CoherencePassService.swift
//  Sprung
//
//  Post-assembly coherence pass service. Executes a single LLM call that
//  scans the completed resume for achievement repetition, summary-highlights
//  alignment, skills-content alignment, emphasis consistency, and narrative flow.
//

import Foundation
import SwiftOpenAI

/// Service that performs a single-call coherence check on a fully-assembled resume.
/// Runs after the user has reviewed and approved all changes.
@MainActor
final class CoherencePassService {

    // MARK: - Minimum Threshold

    /// Minimum number of customized fields before the coherence pass is worthwhile.
    /// Small edits (e.g., changing one highlight) rarely produce cross-section issues.
    static let minimumFieldsForCoherenceCheck = 4

    // MARK: - Public API

    /// Run the coherence pass on a fully-assembled resume.
    ///
    /// - Parameters:
    ///   - resume: The resume with all approved changes applied.
    ///   - targetingPlan: The strategic targeting plan (for alignment checking).
    ///   - jobDescription: The target job description text.
    ///   - llmFacade: The LLM facade for API calls.
    ///   - modelId: The model ID to use (from user settings, never hardcoded).
    /// - Returns: A CoherenceReport with any detected issues.
    func runCoherenceCheck(
        resume: Resume,
        targetingPlan: TargetingPlan?,
        jobDescription: String,
        llmFacade: LLMFacade,
        modelId: String
    ) async throws -> CoherenceReport {
        guard !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "customizationModel",
                operationName: "Coherence Check"
            )
        }

        let resumeText = ResumeTextSnapshotBuilder.buildSnapshot(resume: resume)
        let prompt = buildCoherencePrompt(
            resumeText: resumeText,
            targetingPlan: targetingPlan,
            jobDescription: jobDescription
        )

        do {
            let report = try await llmFacade.executeStructuredWithSchema(
                prompt: prompt,
                modelId: modelId,
                as: CoherenceReport.self,
                schema: CustomizationSchemas.coherenceReport,
                schemaName: "coherence_report"
            )
            Logger.info("[CoherencePass] Completed: \(report.overallCoherence.rawValue), \(report.issues.count) issues", category: .ai)
            return report
        } catch {
            Logger.error("[CoherencePass] LLM call failed: \(error.localizedDescription)", category: .ai)
            // Return a clean report on failure rather than blocking the workflow
            return CoherenceReport(
                issues: [],
                overallCoherence: .good,
                summary: "Coherence check could not be completed."
            )
        }
    }

    // MARK: - Prompt Construction

    private func buildCoherencePrompt(
        resumeText: String,
        targetingPlan: TargetingPlan?,
        jobDescription: String
    ) -> String {
        var sections: [String] = []

        // System instructions
        sections.append("""
        # Role: Resume Coherence Reviewer

        You are a meticulous resume editor performing a final quality check. \
        The resume below has just been customized for a specific job application. \
        Your job is to scan the assembled result and flag coherence issues \
        that slipped through the per-field customization process.

        ## Check Categories

        1. **Achievement Repetition** — Are any accomplishments, metrics, or claims \
        repeated verbatim or near-verbatim across sections? Flag the specific duplicated \
        text and both locations.

        2. **Summary-Highlights Alignment** — Does the objective/summary make claims \
        that aren't substantiated by work highlights? Do highlights demonstrate \
        skills not mentioned in the summary?

        3. **Skills-Content Alignment** — Are skills listed that aren't evidenced in \
        any work entry or project? Are there skills demonstrated in content but \
        missing from the skills section?

        4. **Emphasis Consistency** — Does the resume consistently emphasize the \
        targeting plan's narrative arc? Are there sections that contradict the \
        intended framing?

        5. **Narrative Flow** — Does experience order flow from most to least relevant \
        for this job? Are there jarring transitions between sections?

        6. **Section Redundancy** — Do projects duplicate work highlights? Does the \
        summary restate the first work entry?

        ## Grading

        - **good**: 0-1 low-severity issues. The resume reads as a coherent document.
        - **fair**: 2-3 issues, or 1 high-severity issue. Minor adjustments needed.
        - **poor**: 4+ issues or multiple high-severity issues. Significant rework needed.

        ## Rules

        - Be specific: quote the actual text that's problematic.
        - Locations should use resume path notation (e.g., "summary", "work.0.highlights[2]", "skills.1.keywords").
        - Only flag genuine issues — don't manufacture problems.
        - If the resume is coherent, return overallCoherence "good" with an empty issues array.
        """)

        // Targeting plan context (if available)
        if let plan = targetingPlan {
            sections.append("""
            ---

            ## Targeting Plan (for alignment checking)

            \(plan.formattedForPrompt())
            """)
        }

        // Job description
        if !jobDescription.isEmpty {
            sections.append("""
            ---

            ## Target Job Description

            \(jobDescription)
            """)
        }

        // Full resume text
        sections.append("""
        ---

        ## Assembled Resume

        \(resumeText)
        """)

        return sections.joined(separator: "\n\n")
    }
}
