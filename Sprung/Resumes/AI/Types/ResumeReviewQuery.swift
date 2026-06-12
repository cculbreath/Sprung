//
//  ResumeReviewQuery.swift
//  Sprung
//
import Foundation
/// Centralized prompt management for resume review operations
/// Follows the architecture pattern from ResumeQuery.swift and CoverLetterQuery.swift
@Observable class ResumeReviewQuery {
    // MARK: - Prompt Loading

    private func loadPromptTemplate(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("Failed to load prompt template: \(name)", category: .ai)
            return "Error loading prompt template"
        }
        return content
    }

    private func loadPromptTemplateWithSubstitutions(named name: String, substitutions: [String: String]) -> String {
        var template = loadPromptTemplate(named: name)
        for (key, value) in substitutions {
            template = template.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return template
    }

    // MARK: - General Resume Review Prompts
    /// Build the main review prompt based on review type
    /// - Parameters:
    ///   - reviewType: The type of review to perform
    ///   - resume: The resume to review
    ///   - includeImage: Whether image analysis is available
    ///   - customOptions: Optional custom review options
    /// - Returns: The complete prompt string
    func buildReviewPrompt(
        reviewType: ResumeReviewType,
        resume: Resume,
        includeImage: Bool,
        customOptions: CustomReviewOptions? = nil
    ) -> String {
        guard let jobApp = resume.jobApp else {
            return "Error: No job application associated with this resume."
        }
        var prompt = reviewType.promptTemplate()
        // Handle custom build if necessary
        if reviewType == .custom, let opt = customOptions {
            prompt = buildCustomPrompt(options: opt)
        }
        prompt = prompt.replacingOccurrences(of: "{jobPosition}", with: jobApp.jobPosition)
        prompt = prompt.replacingOccurrences(of: "{companyName}", with: jobApp.companyName)
        prompt = prompt.replacingOccurrences(of: "{jobDescription}", with: jobApp.jobDescription)
        let resumeText = resume.textResume
        prompt = prompt.replacingOccurrences(of: "{resumeText}", with: resumeText)
        // Background docs: knowledge cards enabled for this resume
        let bgDocs = resume.enabledSources.map { "\($0.title):\n\($0.narrative)\n\n" }.joined()
        prompt = prompt.replacingOccurrences(of: "{backgroundDocs}", with: bgDocs)
        // Image context sentence
        let imageText = includeImage
            ? "I've also attached rasterized resume page image(s) so you can assess the visual layout, typography, and overall design professionalism."
            : ""
        prompt = prompt.replacingOccurrences(of: "{includeImage}", with: imageText)
        return prompt
    }
    /// Build custom prompt from options
    private func buildCustomPrompt(options: CustomReviewOptions) -> String {
        // Build prompt based on what components the user wants to include
        var promptComponents: [String] = []
        if options.includeJobListing {
            promptComponents.append("""
            Job Description:
            {jobDescription}
            """)
        }
        if options.includeResumeText {
            promptComponents.append("""
            Resume Content:
            {resumeText}
            """)
        }
        if options.includeResumeImage {
            promptComponents.append("{includeImage}")
        }
        let basePrompt = """
        Please review this resume for the position of {jobPosition} at {companyName}.
        \(promptComponents.joined(separator: "\n\n"))
        Custom Instructions:
        \(options.customPrompt.isEmpty ? "Please provide a comprehensive resume review." : options.customPrompt)
        """
        return basePrompt
    }
    // MARK: - Fix Overflow Prompts
    /// Build the fix fits prompt for standard (non-Grok) models
    /// - Parameters:
    ///   - skillsJsonString: JSON representation of skills
    ///   - pageCount: Current rendered page count of the resume
    ///   - pageLimit: Page budget from the template manifest
    ///   - editableNodeIds: IDs of the only nodes the model may modify
    ///   - writersVoice: Canonical voice block (empty when unavailable)
    ///   - allowEntityMerge: Whether to allow merging redundant entries
    /// - Returns: Complete prompt for fix fits operation
    func buildFixFitsPrompt(
        skillsJsonString: String,
        pageCount: Int,
        pageLimit: Int,
        editableNodeIds: Set<String>,
        writersVoice: String,
        allowEntityMerge: Bool = false
    ) -> String {
        let mergeInstructions = allowEntityMerge ? loadPromptTemplate(named: "resume_merge_instructions") : ""
        let prompt = loadPromptTemplateWithSubstitutions(named: "resume_fix_fits", substitutions: [
            "skillsJsonString": skillsJsonString,
            "mergeInstructions": mergeInstructions
        ])
        return prompt + fixFitsConstraintSections(
            pageCount: pageCount,
            pageLimit: pageLimit,
            editableNodeIds: editableNodeIds,
            writersVoice: writersVoice
        )
    }
    /// Build the Grok-specific fix fits prompt (text-only approach)
    /// - Parameters:
    ///   - skillsJsonString: JSON representation of skills
    ///   - pageCount: Current rendered page count of the resume
    ///   - pageLimit: Page budget from the template manifest
    ///   - editableNodeIds: IDs of the only nodes the model may modify
    ///   - writersVoice: Canonical voice block (empty when unavailable)
    ///   - allowEntityMerge: Whether to allow merging redundant entries
    /// - Returns: Complete prompt for Grok fix fits operation
    func buildGrokFixFitsPrompt(
        skillsJsonString: String,
        pageCount: Int,
        pageLimit: Int,
        editableNodeIds: Set<String>,
        writersVoice: String,
        allowEntityMerge: Bool = false
    ) -> String {
        let overflowGuidance = "The rendered resume currently spans \(pageCount) page\(pageCount == 1 ? "" : "s"); the limit is \(pageLimit) page\(pageLimit == 1 ? "" : "s"). Tighten the skills content so the resume fits within the limit."
        let mergeInstructions = allowEntityMerge ? loadPromptTemplate(named: "resume_merge_instructions") : ""
        let prompt = loadPromptTemplateWithSubstitutions(named: "resume_grok_fix_fits", substitutions: [
            "overflowGuidance": overflowGuidance,
            "skillsJsonString": skillsJsonString,
            "mergeInstructions": mergeInstructions
        ])
        return prompt + fixFitsConstraintSections(
            pageCount: pageCount,
            pageLimit: pageLimit,
            editableNodeIds: editableNodeIds,
            writersVoice: writersVoice
        )
    }
    /// Shared constraint sections appended to both fix fits prompt variants:
    /// page budget, editable-node restriction, and the writer's voice anchor.
    private func fixFitsConstraintSections(
        pageCount: Int,
        pageLimit: Int,
        editableNodeIds: Set<String>,
        writersVoice: String
    ) -> String {
        var sections: [String] = []
        sections.append("""

        PAGE BUDGET:
        The rendered resume currently spans \(pageCount) page\(pageCount == 1 ? "" : "s") but must fit within \(pageLimit) page\(pageLimit == 1 ? "" : "s"). Reduce the skills content enough to bring the resume within that budget.
        """)
        let idList = editableNodeIds.sorted().joined(separator: "\n- ")
        sections.append("""

        EDITABLE ENTRIES:
        You may ONLY revise or merge entries with the following ids. Return revisions for these ids exclusively; any other entry must be left untouched:
        - \(idList)
        """)
        if !writersVoice.isEmpty {
            sections.append("\n\(writersVoice)\n\nAll rewritten titles and descriptions MUST match the voice characteristics above.")
        }
        return sections.joined(separator: "\n")
    }
    // MARK: - Console Print Friendly Methods
    /// Creates a console-friendly version of the prompt with truncated long strings
    func consoleFriendlyPrompt(_ fullPrompt: String) -> String {
        var truncatedPrompt = fullPrompt
        // Truncate job description if present
        if truncatedPrompt.contains("{jobDescription}") {
            let truncatedJobDesc = "[Job description truncated...]"
            truncatedPrompt = truncatedPrompt.replacingOccurrences(of: "{jobDescription}", with: truncatedJobDesc)
        }
        // Truncate resume text if present
        if truncatedPrompt.contains("{resumeText}") {
            let truncatedResumeText = "[Resume text truncated...]"
            truncatedPrompt = truncatedPrompt.replacingOccurrences(of: "{resumeText}", with: truncatedResumeText)
        }
        // Truncate skills JSON if present in fix fits prompts
        let skillsPattern = "Here are the current skills and expertise entries in JSON format:"
        if let skillsRange = truncatedPrompt.range(of: skillsPattern) {
            let fromSkills = truncatedPrompt[skillsRange.upperBound...]
            if let taskRange = fromSkills.range(of: "TASK:") {
                let skillsJson = String(fromSkills[..<taskRange.lowerBound])
                let truncatedSkillsJson = truncateString(skillsJson, maxLength: 300)
                truncatedPrompt = truncatedPrompt.replacingOccurrences(of: skillsJson, with: truncatedSkillsJson)
            }
        }
        return truncatedPrompt
    }
    /// Helper method to truncate strings with ellipsis
    private func truncateString(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength {
            return string
        }
        let truncated = String(string.prefix(maxLength))
        return truncated + "..."
    }
}
