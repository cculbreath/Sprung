//
//  CompleteDossierSectionTool.swift
//  Sprung
//
//  Tool for incrementally building the candidate dossier one section at a time.
//  This allows the LLM to complete sections in separate turns with focused context,
//  reducing the likelihood of missing fields when submitting the full dossier.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct CompleteDossierSectionTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Complete a single section of the candidate dossier. Call this tool once per section
                after gathering the relevant information through conversation.

                WORKFLOW:
                1. After strengths synthesis discussion → call with section="strengths"
                2. After pitfalls analysis discussion → call with section="pitfalls"
                3. After gathering job context → call with section="job_context"
                4. After gathering preferences → call with section="work_preferences", "availability", etc.
                5. When all required sections complete → call submit_dossier to validate and finalize

                Each section call marks progress. Required sections: job_context, strengths, pitfalls.
                """,
            properties: [
                "section": JSONSchema(
                    type: .string,
                    description: """
                        The dossier section to complete. Required sections are: job_context, strengths, pitfalls.
                        Optional sections are: work_preferences, availability, unique_circumstances, notes.
                        """,
                    enum: DossierSection.allCases.map { $0.rawValue }
                ),
                "content": JSONSchema(
                    type: .string,
                    description: """
                        The content for this section. Refer to section-specific requirements:

                        job_context (200+ chars): Why looking, what seeking, priorities, non-negotiables.
                        Example: "Seeking greater technical ownership and product impact..."

                        strengths (500+ chars): 2-4 paragraphs synthesizing strategic strengths with evidence.
                        Each strength should include: category, evidence, why it matters, how to use it.

                        pitfalls (500+ chars): 2-4 paragraphs documenting concerns with mitigations.
                        Each pitfall should include: the concern, why it matters, mitigation strategy.

                        work_preferences: Remote/hybrid/onsite preferences, relocation willingness.
                        availability: Start timing, notice period, scheduling constraints.
                        unique_circumstances: Context for gaps, pivots, visa, sabbatical, etc.
                        notes: Private interviewer observations, deal-breakers, cultural fit.
                        """
                )
            ],
            required: ["section", "content"],
            additionalProperties: false
        )
    }()

    private let eventBus: EventCoordinator
    private let candidateDossierStore: CandidateDossierStore

    var name: String { OnboardingToolName.completeDossierSection.rawValue }
    var description: String {
        """
        Complete a single section of the candidate dossier. Use this after discussing each topic
        (strengths, pitfalls, job context, etc.) to save that section before moving on.
        Required sections: job_context (200+ chars), strengths (500+ chars), pitfalls (500+ chars).
        Call submit_dossier when all required sections are complete.
        """
    }
    var parameters: JSONSchema { Self.schema }

    init(eventBus: EventCoordinator, candidateDossierStore: CandidateDossierStore) {
        self.eventBus = eventBus
        self.candidateDossierStore = candidateDossierStore
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Parse section
        guard let sectionRaw = params["section"].string,
              let section = DossierSection(rawValue: sectionRaw) else {
            return ToolResultHelpers.executionFailed(
                "Invalid section. Must be one of: \(DossierSection.allCases.map { $0.rawValue }.joined(separator: ", "))"
            )
        }

        // Get content
        let content = try ToolResultHelpers.requireString(
            params["content"].string,
            named: "content"
        )

        // Validate minimum length for required sections
        if section.minimumLength > 0 && content.count < section.minimumLength {
            return ToolResultHelpers.executionFailed(
                "\(section.displayName) requires at least \(section.minimumLength) characters. " +
                "Provided: \(content.count) characters. Please expand with more detail."
            )
        }

        // Persist section
        let dossier = await MainActor.run {
            candidateDossierStore.updateSection(section, content: content)
        }
        Logger.info("📋 Dossier section '\(section.rawValue)' completed (\(content.count) chars)", category: .ai)

        // Mark associated objective complete if applicable
        if let objectiveId = section.associatedObjective {
            await eventBus.publish(.objective(.statusUpdateRequested(
                id: objectiveId.rawValue,
                status: "completed",
                source: "tool_execution",
                notes: "\(section.displayName) section completed",
                details: nil
            )))
            Logger.info("✅ Objective \(objectiveId.rawValue) marked complete via section completion", category: .ai)
        }

        // Build response
        var response = JSON()
        response["status"].string = "section_completed"
        response["section"].string = section.rawValue
        response["charCount"].int = content.count
        response["wordCount"].int = content.split(separator: " ").count

        // Check overall progress
        let completedSections = await MainActor.run { candidateDossierStore.completedSections() }
        let missingSections = await MainActor.run { candidateDossierStore.missingSections() }

        response["completedSections"].arrayObject = completedSections.map { $0.rawValue }
        response["missingSections"].arrayObject = missingSections.map { $0.rawValue }
        response["totalWordCount"].int = dossier.wordCount

        if missingSections.isEmpty {
            response["message"].string = "All required sections complete! Call submit_dossier to validate and finalize."
        } else {
            response["message"].string = "Section saved. Remaining required: \(missingSections.map { $0.rawValue }.joined(separator: ", "))"
        }

        return .immediate(response)
    }
}
