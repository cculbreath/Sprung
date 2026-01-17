//
//  TitleOptionsGenerator.swift
//  Sprung
//
//  Generator for professional title set selection.
//  Selects the most appropriate title set from the user's library.
//

import Foundation

// MARK: - Response Types

private struct TitleSelectionResponse: Codable {
    let selectedId: String
    let rationale: String
}

/// Selects the most appropriate professional title set from the user's library.
/// Analyzes experience and available title sets to recommend the best match.
@MainActor
final class TitleOptionsGenerator: BaseSectionGenerator {
    override var displayName: String { "Professional Titles" }

    init() {
        super.init(sectionKey: .custom)
    }

    // MARK: - Task Creation

    /// Creates a single task for title selection (only if title sets exist)
    override func createTasks(context: SeedGenerationContext) -> [GenerationTask] {
        guard !context.titleSets.isEmpty else {
            Logger.info("TitleOptionsGenerator: No title sets in library, skipping", category: .ai)
            return []
        }

        return [
            GenerationTask(
                id: UUID(),
                section: .custom,
                targetId: nil,
                displayName: "Select Title Set",
                status: .pending
            )
        ]
    }

    // MARK: - Execution

    override func execute(
        task: GenerationTask,
        context: SeedGenerationContext,
        config: GeneratorExecutionConfig
    ) async throws -> GeneratedContent {
        guard !context.titleSets.isEmpty else {
            throw GeneratorError.missingContext("No title sets available in library")
        }

        let taskContext = buildTaskContext(context: context)
        let titleSetOptions = buildTitleSetOptions(context: context)

        let systemPrompt = """
            You are an expert resume strategist helping select the best professional identity.
            """

        let taskPrompt = """
            ## Task: Select Professional Title Set

            Choose the single most appropriate title set from the user's library for their resume header.
            Each title set contains exactly 4 words that define their professional identity.

            ## Candidate Context

            \(taskContext)

            ## Available Title Sets

            \(titleSetOptions)

            ## Instructions

            1. Review the candidate's background and experience
            2. Consider which title set best represents their professional identity
            3. Select the ONE title set that would be most effective for general-purpose use
            4. Provide brief rationale for your selection

            Return JSON with the selected title set ID and your reasoning.
            """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "selectedId": ["type": "string", "description": "The UUID of the selected title set"],
                "rationale": ["type": "string", "description": "Brief explanation for the selection"]
            ],
            "required": ["selectedId", "rationale"],
            "additionalProperties": false
        ]

        let response: TitleSelectionResponse = try await executeStructuredRequest(
            taskPrompt: taskPrompt,
            systemPrompt: systemPrompt,
            config: config,
            responseType: TitleSelectionResponse.self,
            schema: schema,
            schemaName: "title_selection"
        )

        // Find the selected title set
        guard let selectedRecord = context.titleSets.first(where: { $0.id.uuidString == response.selectedId }) else {
            Logger.warning("TitleOptionsGenerator: Selected ID '\(response.selectedId)' not found, using first", category: .ai)
            let fallbackRecord = context.titleSets[0]
            let fallbackSet = TitleSet(
                titles: fallbackRecord.words.map { $0.text },
                emphasis: .balanced,
                suggestedFor: []
            )
            return GeneratedContent(type: .titleSets([fallbackSet]))
        }

        Logger.info("TitleOptionsGenerator: Selected '\(selectedRecord.compactDisplayString)' - \(response.rationale)", category: .ai)

        let selectedSet = TitleSet(
            titles: selectedRecord.words.map { $0.text },
            emphasis: .balanced,
            suggestedFor: []
        )

        return GeneratedContent(type: .titleSets([selectedSet]))
    }

    // MARK: - Regeneration

    override func regenerate(
        task: GenerationTask,
        originalContent: GeneratedContent,
        feedback: String?,
        context: SeedGenerationContext,
        config: GeneratorExecutionConfig
    ) async throws -> GeneratedContent {
        guard !context.titleSets.isEmpty else {
            throw GeneratorError.missingContext("No title sets available in library")
        }

        let taskContext = buildTaskContext(context: context)
        let titleSetOptions = buildTitleSetOptions(context: context)
        let regenerationContext = buildRegenerationContext(originalContent: originalContent, feedback: feedback)

        let systemPrompt = "You are an expert resume strategist helping select the best professional identity."

        let taskPrompt = """
            ## Task: Re-select Professional Title Set

            The previous selection was rejected. Choose a different title set from the library.

            ## Candidate Context

            \(taskContext)

            ## Available Title Sets

            \(titleSetOptions)

            \(regenerationContext)

            ## Instructions

            1. Consider the feedback about the previous selection
            2. Select a DIFFERENT title set that better addresses the concerns
            3. Provide rationale for the new selection
            """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "selectedId": ["type": "string", "description": "The UUID of the selected title set"],
                "rationale": ["type": "string", "description": "Brief explanation for the selection"]
            ],
            "required": ["selectedId", "rationale"],
            "additionalProperties": false
        ]

        let response: TitleSelectionResponse = try await executeStructuredRequest(
            taskPrompt: taskPrompt,
            systemPrompt: systemPrompt,
            config: config,
            responseType: TitleSelectionResponse.self,
            schema: schema,
            schemaName: "title_selection"
        )

        // Find the selected title set
        guard let selectedRecord = context.titleSets.first(where: { $0.id.uuidString == response.selectedId }) else {
            Logger.warning("TitleOptionsGenerator: Selected ID '\(response.selectedId)' not found, using first", category: .ai)
            let fallbackRecord = context.titleSets[0]
            let fallbackSet = TitleSet(
                titles: fallbackRecord.words.map { $0.text },
                emphasis: .balanced,
                suggestedFor: []
            )
            return GeneratedContent(type: .titleSets([fallbackSet]))
        }

        Logger.info("TitleOptionsGenerator: Re-selected '\(selectedRecord.compactDisplayString)' - \(response.rationale)", category: .ai)

        let selectedSet = TitleSet(
            titles: selectedRecord.words.map { $0.text },
            emphasis: .balanced,
            suggestedFor: []
        )

        return GeneratedContent(type: .titleSets([selectedSet]))
    }

    // MARK: - Apply to Defaults

    override func apply(content: GeneratedContent, to defaults: inout ExperienceDefaults) {
        guard case .titleSets(let titleSets) = content.type else {
            Logger.warning("TitleOptionsGenerator: content type mismatch", category: .ai)
            return
        }

        // Title sets are stored in InferenceGuidance, not ExperienceDefaults
        // This apply method is a no-op since titles are handled separately
        Logger.info("Selected \(titleSets.count) title set(s) (stored separately)", category: .ai)
    }

    // MARK: - Context Building

    private func buildTaskContext(context: SeedGenerationContext) -> String {
        var lines: [String] = []

        // Recent job titles
        let workEntries = context.timelineEntries(for: .work)
        if !workEntries.isEmpty {
            lines.append("### Recent Positions")
            for entry in workEntries.prefix(5) {
                let title = entry["title"].stringValue
                let company = entry["company"].stringValue
                if !title.isEmpty {
                    lines.append("- \(title)\(company.isEmpty ? "" : " at \(company)")")
                }
            }
        }

        // Top skills
        if !context.skills.isEmpty {
            lines.append("\n### Top Skills")
            let topSkills = context.skills.prefix(15).map { $0.canonical }
            lines.append(topSkills.joined(separator: ", "))
        }

        // Education
        let eduEntries = context.timelineEntries(for: .education)
        if !eduEntries.isEmpty {
            lines.append("\n### Education")
            for entry in eduEntries.prefix(2) {
                let studyType = entry["studyType"].stringValue
                let area = entry["area"].stringValue
                if !studyType.isEmpty || !area.isEmpty {
                    lines.append("- \(studyType) in \(area)")
                }
            }
        }

        // Existing summary if available
        if !context.applicantProfile.summary.isEmpty {
            lines.append("\n### Current Summary")
            lines.append(context.applicantProfile.summary)
        }

        return lines.joined(separator: "\n")
    }

    private func buildTitleSetOptions(context: SeedGenerationContext) -> String {
        var lines: [String] = []

        for (index, record) in context.titleSets.enumerated() {
            let words = record.words.map { $0.text }
            lines.append("\(index + 1). ID: \(record.id.uuidString)")
            lines.append("   Titles: \(words.joined(separator: " · "))")
            if let notes = record.notes, !notes.isEmpty {
                lines.append("   Notes: \(notes)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
