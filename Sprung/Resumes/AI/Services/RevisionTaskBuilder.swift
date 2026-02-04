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
            return generateSkillsPrompt(for: revNode, skills: skills)
        case .skillKeywords:
            return generateSkillKeywordsPrompt(for: revNode, skills: skills)
        case .titles:
            return generateTitlesPrompt(for: revNode, titleSets: titleSets)
        case .generic:
            return generateGenericPrompt(for: revNode)
        }
    }

    /// Generate prompt for skills section revision.
    private func generateSkillsPrompt(for revNode: ExportedReviewNode, skills: [Skill]) -> String {
        let skillBank = formatSkillBank(skills)

        return """
        Re-select skills from the Skill Bank for each category to better match this job posting.

        CRITICAL CONSTRAINTS:
        - PRESERVE the existing category names exactly as shown below
        - DO NOT rename, merge, or reorganize categories
        - ONLY change which skills appear under each category
        - Select skills ONLY from the Skill Bank below - do NOT invent skills
        - Prefer higher-proficiency skills (expert > proficient > familiar) when multiple skills match the job

        ## Available Skills from Skill Bank

        \(skillBank)

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
    private func generateSkillKeywordsPrompt(for revNode: ExportedReviewNode, skills: [Skill]) -> String {
        let categoryName = extractCategoryName(from: revNode)
        let matchedCategory = matchCategory(from: revNode, skills: skills)

        // Build primary skills list (matching category)
        let primarySkills: [Skill]
        let otherSkills: [Skill]
        if let category = matchedCategory {
            primarySkills = skills.filter { $0.category == category }
                .sorted { ($0.proficiency.sortOrder, $0.canonical) < ($1.proficiency.sortOrder, $1.canonical) }
            otherSkills = skills.filter { $0.category != category }
        } else {
            primarySkills = []
            otherSkills = skills
        }

        var skillReference = ""
        if !primarySkills.isEmpty {
            let lines = primarySkills.map { "- \($0.canonical) (\($0.proficiency.rawValue))" }
            skillReference += """
            ## Skills in "\(categoryName)" Category
            \(lines.joined(separator: "\n"))
            """
        }

        if !otherSkills.isEmpty {
            let otherNames = otherSkills
                .sorted { ($0.proficiency.sortOrder, $0.canonical) < ($1.proficiency.sortOrder, $1.canonical) }
                .map { $0.canonical }
            skillReference += "\n\n## Other Available Skills (secondary reference)\n\(otherNames.joined(separator: ", "))"
        }

        return """
        Re-select skills from the Skill Bank for the "\(categoryName)" category.
        Choose skills that best match the job requirements.
        ONLY use skills from the Skill Bank below - do NOT invent new skills.
        Prefer higher-proficiency skills (expert > proficient > familiar) when multiple skills match.

        \(skillReference)

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
        if titleSets.isEmpty {
            return """
            No title sets are available in the Title Set Library. Propose original job titles that best position the applicant for this specific job based on the job description and the applicant's background.

            Current titles: \(revNode.value)

            Return a JSON object with this structure:
            {
              "id": "\(revNode.id)",
              "oldValue": "\(escapeForJSON(revNode.value))",
              "newValue": "{{proposed titles as period-separated string}}",
              "valueChanged": true,
              "why": "explanation of why these titles were chosen",
              "treePath": "\(revNode.path)",
              "nodeType": "scalar"
            }
            """
        }

        // Build title set reference
        let titleSetReference = titleSets.enumerated().map { index, set in
            let emphasis = set.emphasis.displayName
            let suggestedUses = set.suggestedFor.isEmpty ? "general" : set.suggestedFor.joined(separator: ", ")
            return "Set \(index): \(set.displayString) [Emphasis: \(emphasis), Suggested for: \(suggestedUses)]"
        }.joined(separator: "\n")

        return """
        Select the best title set from the Title Set Library for this job application.

        Evaluate which set best positions the applicant for this specific job based on:
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

    /// Format the full skill bank grouped by category with proficiency levels.
    private func formatSkillBank(_ skills: [Skill]) -> String {
        let grouped = Dictionary(grouping: skills) { $0.category }
        var sections: [String] = []

        for category in SkillCategory.allCases {
            guard let categorySkills = grouped[category], !categorySkills.isEmpty else { continue }
            let sorted = categorySkills.sorted {
                ($0.proficiency.sortOrder, $0.canonical) < ($1.proficiency.sortOrder, $1.canonical)
            }
            var lines = ["### \(category.rawValue)"]
            for skill in sorted {
                lines.append("- \(skill.canonical) (\(skill.proficiency.rawValue))")
            }
            sections.append(lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    /// Match a review node's category name to a SkillCategory.
    private func matchCategory(from revNode: ExportedReviewNode, skills: [Skill]) -> SkillCategory? {
        let name = extractCategoryName(from: revNode).lowercased()
        return SkillCategory.allCases.first {
            name.contains($0.rawValue.lowercased()) || $0.rawValue.lowercased().contains(name)
        }
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
