//
//  RevisionTaskBuilder.swift
//  Sprung
//
//  Builds RevisionTasks from ExportedReviewNodes with node-type-specific prompts.
//

import Foundation

@MainActor
final class RevisionTaskBuilder {

    // MARK: - Public API

    /// Build revision tasks from exported review nodes with node-type-specific prompts.
    /// - Parameters:
    ///   - revNodes: The nodes to build tasks for
    ///   - resume: The resume being customized
    ///   - jobDescription: The target job description
    ///   - skills: Available skills from the Skill Bank
    ///   - titleSets: Available title sets from the library
    ///   - phase: The current phase number
    /// - Returns: Array of revision tasks with appropriate prompts
    func buildTasks(
        from revNodes: [ExportedReviewNode],
        resume: Resume,
        jobDescription: String,
        skills: [Skill],
        titleSets: [TitleSet],
        phase: Int
    ) -> [RevisionTask] {
        revNodes.map { revNode in
            let nodeType = detectNodeType(for: revNode)
            let taskPrompt = generatePrompt(
                for: revNode,
                nodeType: nodeType,
                skills: skills,
                titleSets: titleSets
            )

            return RevisionTask(
                revNode: revNode,
                taskPrompt: taskPrompt,
                nodeType: nodeType,
                phase: phase
            )
        }
    }

    // MARK: - Node Type Detection

    /// Detect the node type based on path and bundling status.
    private func detectNodeType(for revNode: ExportedReviewNode) -> RevisionNodeType {
        let pathLower = revNode.path.lowercased()

        // Skills section bundled → whole skills section
        if pathLower.contains("skills") && revNode.isBundled {
            return .skills
        }

        // Skills path ending with keywords → skill keywords
        if pathLower.contains("skills") && pathLower.hasSuffix("keywords") {
            return .skillKeywords
        }

        // Title-related paths
        if pathLower.contains("jobtitles") || pathLower.contains("titles") {
            return .titles
        }

        return .generic
    }

    // MARK: - Prompt Generation

    /// Generate the task-specific prompt based on node type.
    private func generatePrompt(
        for revNode: ExportedReviewNode,
        nodeType: RevisionNodeType,
        skills: [Skill],
        titleSets: [TitleSet]
    ) -> String {
        switch nodeType {
        case .skills:
            return generateSkillsPrompt(for: revNode)
        case .skillKeywords:
            return generateSkillKeywordsPrompt(for: revNode)
        case .titles:
            return generateTitlesPrompt(for: revNode, titleSets: titleSets)
        case .generic:
            return generateGenericPrompt(for: revNode)
        }
    }

    /// Generate prompt for skills section revision.
    private func generateSkillsPrompt(for revNode: ExportedReviewNode) -> String {
        """
        Re-select skills from the Skill Bank for each category to better match this job posting.

        CRITICAL CONSTRAINTS:
        - PRESERVE the existing category names exactly as shown below
        - DO NOT rename, merge, or reorganize categories
        - ONLY change which skills appear under each category
        - Select skills from the Skill Bank that are most relevant to the job requirements
        - Do NOT invent skills - only select from the Skill Bank provided in the preamble

        Current skills on resume (preserve these category names):
        \(revNode.value)

        Your task: For each existing category, select the most job-relevant skills from the Skill Bank.
        Keep the same category names but optimize the skill selection within each.

        Return a JSON object with this structure:
        {
          "id": "\(revNode.id)",
          "oldValue": "\(escapeForJSON(revNode.value))",
          "newValue": "{{categories with updated skills as comma-separated list}}",
          "valueChanged": true,
          "why": "explanation of skill selection changes (not category changes)",
          "treePath": "\(revNode.path)",
          "nodeType": "list",
          "newValueArray": ["ExistingCategory1: skill1, skill2", "ExistingCategory2: skill3, skill4"]
        }

        Remember: Category names must match the original exactly. Only the skills within each category should change.
        """
    }

    /// Generate prompt for skill keywords revision.
    private func generateSkillKeywordsPrompt(for revNode: ExportedReviewNode) -> String {
        // Extract category name from display name or path
        let categoryName = extractCategoryName(from: revNode)

        return """
        Re-select skills from the Skill Bank for the "\(categoryName)" category.
        Choose skills that best match the job requirements.
        ONLY use skills from the Skill Bank - do not invent new skills.

        Current skills: \(revNode.value)

        Return a JSON object with this structure:
        {
          "id": "\(revNode.id)",
          "oldValue": "\(escapeForJSON(revNode.value))",
          "newValue": "{{new skill selection as comma-separated list}}",
          "valueChanged": true,
          "why": "explanation of skill selection changes",
          "treePath": "\(revNode.path)",
          "nodeType": "list",
          "newValueArray": ["skill1", "skill2", "skill3"]
        }
        """
    }

    /// Generate prompt for titles revision.
    private func generateTitlesPrompt(for revNode: ExportedReviewNode, titleSets: [TitleSet]) -> String {
        // Build title set reference
        let titleSetReference = titleSets.enumerated().map { index, set in
            let emphasis = set.emphasis.displayName
            let suggestedUses = set.suggestedFor.isEmpty ? "general" : set.suggestedFor.joined(separator: ", ")
            return "Set \(index): \(set.displayString) [Emphasis: \(emphasis), Suggested for: \(suggestedUses)]"
        }.joined(separator: "\n")

        return """
        Select the best title set from the Title Set Library for this job application.

        Available sets are provided in the preamble. Evaluate which set best positions the applicant for this specific job based on:
        - Job requirements and keywords
        - Title set emphasis alignment
        - Suggested use cases

        Title Set Library Reference:
        \(titleSetReference)

        Current titles: \(revNode.value)

        Return a JSON object with this structure:
        {
          "id": "\(revNode.id)",
          "oldValue": "\(escapeForJSON(revNode.value))",
          "newValue": "{{titles from selected set as period-separated string}}",
          "valueChanged": true,
          "why": "explanation of why this title set was selected",
          "treePath": "\(revNode.path)",
          "nodeType": "scalar"
        }

        Include "selectedSetIndex" in your response indicating which set (0-indexed) you selected.
        """
    }

    /// Generate prompt for generic field revision.
    private func generateGenericPrompt(for revNode: ExportedReviewNode) -> String {
        """
        Revise this resume content for the target job.

        Field: \(revNode.displayName)
        Path: \(revNode.path)
        Current value: \(revNode.value)

        Maintain the applicant's voice (see Voice section in preamble).
        Use evidence from Knowledge Cards only - no fabricated metrics.

        Return a JSON object with this structure:
        {
          "id": "\(revNode.id)",
          "oldValue": "\(escapeForJSON(revNode.value))",
          "newValue": "{{proposed revision}}",
          "valueChanged": true,
          "why": "explanation of changes",
          "treePath": "\(revNode.path)",
          "nodeType": "\(revNode.isContainer ? "list" : "scalar")"
        }

        If no changes are needed, set "valueChanged" to false and copy the current value to "newValue".
        """
    }

    // MARK: - Helpers

    /// Extract category name from display name or path.
    private func extractCategoryName(from revNode: ExportedReviewNode) -> String {
        // Try display name first
        if !revNode.displayName.isEmpty && revNode.displayName != revNode.path {
            return revNode.displayName
        }

        // Extract from path (e.g., "skills.0.keywords" -> look for parent name)
        let components = revNode.path.split(separator: ".")
        if components.count >= 2 {
            // Return the second-to-last meaningful component
            return String(components[components.count - 2])
        }

        return "Skills"
    }

    /// Escape string for inclusion in JSON template.
    private func escapeForJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
