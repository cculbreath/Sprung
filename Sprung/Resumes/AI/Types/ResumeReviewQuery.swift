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
        if includeImage {
            prompt += "\n\nAdditionally, I am including a PDF image of the resume for visual context."
        }
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
    ///   - allowEntityMerge: Whether to allow merging redundant entries
    /// - Returns: Complete prompt for fix fits operation
    func buildFixFitsPrompt(skillsJsonString: String, allowEntityMerge: Bool = false) -> String {
        let mergeInstructions = allowEntityMerge ? loadPromptTemplate(named: "resume_merge_instructions") : ""
        return loadPromptTemplateWithSubstitutions(named: "resume_fix_fits", substitutions: [
            "skillsJsonString": skillsJsonString,
            "mergeInstructions": mergeInstructions
        ])
    }
    /// Build the Grok-specific fix fits prompt (text-only approach)
    /// - Parameters:
    ///   - skillsJsonString: JSON representation of skills
    ///   - overflowLineCount: Number of overflowing lines
    ///   - allowEntityMerge: Whether to allow merging redundant entries
    /// - Returns: Complete prompt for Grok fix fits operation
    func buildGrokFixFitsPrompt(skillsJsonString: String, overflowLineCount: Int = 0, allowEntityMerge: Bool = false) -> String {
        let overflowGuidance = overflowLineCount > 0
            ? "Visual analysis indicates approximately \(overflowLineCount) lines of text are overflowing the intended space. Focus your editing efforts on reducing content by roughly this amount."
            : "Visual analysis indicates the content boundaries are overlapping but no significant text overflow. Make minimal adjustments to ensure clean spacing."
        let mergeInstructions = allowEntityMerge ? loadPromptTemplate(named: "resume_merge_instructions") : ""
        return loadPromptTemplateWithSubstitutions(named: "resume_grok_fix_fits", substitutions: [
            "overflowGuidance": overflowGuidance,
            "skillsJsonString": skillsJsonString,
            "mergeInstructions": mergeInstructions
        ])
    }
    // MARK: - Content Fit Check Prompt
    /// Build the contents fit prompt for checking if content fits on page
    /// - Returns: Complete prompt for contents fit check
    func buildContentsFitPrompt() -> String {
        return loadPromptTemplate(named: "resume_contents_fit")
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
