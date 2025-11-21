//
//  ResumeReviewQuery.swift
//  Sprung
//
import Foundation
/// Centralized prompt management for resume review operations
/// Follows the architecture pattern from ResumeQuery.swift and CoverLetterQuery.swift
@Observable class ResumeReviewQuery {

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
        let mergeInstructions = allowEntityMerge ? buildMergeInstructions() : ""

        return """
        You are an expert resume optimizer specializing in content efficiency. Your task is to analyze and revise skills entries to ensure they fit properly within the allocated space while maintaining maximum impact.
        Here are the current skills and expertise entries in JSON format:
        \(skillsJsonString)
        TASK:
        Revise the skills and expertise content to be more concise while preserving meaning and impact. Focus on:
        1. Shortening verbose descriptions without losing key information
        2. Using more concise language and removing redundant words
        3. Maintaining technical accuracy and professional tone
        4. Ensuring each revision is clearly more concise than the original
        IMPORTANT FORMATTING REQUIREMENTS:
        - Entry titles typically display about 28 characters per line before wrapping
        - Entry descriptions typically display about 44 characters per line before wrapping
        - Each entry starts on its own line
        - Aim to reduce the overall character count while maintaining impact
        \(mergeInstructions)
        RESPONSE FORMAT:
        You must respond with a valid JSON object containing exactly this structure:
        {
          "revised_skills_and_expertise": [
            {
              "id": "exact_uuid_from_input",
              "new_title": "revised title or null if no change",
              "new_description": "revised description or null if no change",
              "original_title": "original title from input",
              "original_description": "original description from input"
            }
          ]
        }
        - Use the exact UUID from the input data
        - Set new_title to null if no revision is needed for the title
        - Set new_description to null if no revision is needed for the description
        - Include original_title and original_description for reference
        - Do not add any text outside the JSON object
        """
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

        let mergeInstructions = allowEntityMerge ? buildMergeInstructions() : ""

        return """
        You are an expert resume optimizer specializing in content efficiency for tight layouts. Your task is to analyze and revise skills entries to ensure they fit properly within the allocated space.
        CONTEXT:
        \(overflowGuidance)
        Here are the current skills and expertise entries in JSON format:
        \(skillsJsonString)
        TASK:
        Revise the skills and expertise content to be more concise while preserving meaning and impact. Since no visual reference is available, use these guidelines:
        1. Entry titles should be concise (aim for under 28 characters when possible)
        2. Entry descriptions should be efficient (aim for under 88 characters for two-line entries)
        3. Remove redundant words and use active, concise language
        4. Maintain technical accuracy and professional tone
        5. Focus on the most impactful content
        \(mergeInstructions)
        RESPONSE FORMAT:
        You must respond with a valid JSON object containing exactly this structure:
        {
          "revised_skills_and_expertise": [
            {
              "id": "exact_uuid_from_input",
              "new_title": "revised title or null if no change",
              "new_description": "revised description or null if no change",
              "original_title": "original title from input",
              "original_description": "original description from input"
            }
          ]
        }
        - Use the exact UUID from the input data
        - Set new_title to null if no revision is needed for the title
        - Set new_description to null if no revision is needed for the description
        - Include original_title and original_description for reference
        - Do not add any text outside the JSON object
        """
    }

    /// Build the merge instructions for fix fits operations
    private func buildMergeInstructions() -> String {
        return """

        ENTITY MERGE OPTION:
        You are allowed to merge two redundant or conceptually overlapping skill entries if it will help with fit and improve the resume's overall strength. When merging:
        - Each skill entry in the JSON contains: id, title, description, original_title, and original_description
        - Only merge skill entries that are truly redundant or where combining them creates a stronger, more comprehensive statement
        - Combine the best elements of both entries into a single, more impactful skill entry
        - The merged entry should preserve all unique aspects of both original entries
        - Only ONE merge operation is allowed per request
        - If you perform a merge, include a "merge_operation" object in your response with:
          {
            "skill_to_keep_id": "uuid_of_entry_to_keep",
            "skill_to_delete_id": "uuid_of_entry_to_delete",
            "merged_title": "new_combined_title",
            "merged_description": "new_combined_description",
            "merge_reason": "explanation_of_why_merged"
          }
        - If no merge is beneficial, omit the merge_operation object entirely
        """
    }

    // MARK: - Content Fit Check Prompt
    /// Build the contents fit prompt for checking if content fits on page
    /// - Returns: Complete prompt for contents fit check
    func buildContentsFitPrompt() -> String {
        return """
        You are an expert document layout analyzer. Examine the attached resume image, specifically the left-column 'Skills and Expertise' and 'Education' sections

        Your task is to determine if this section fits properly and estimate any overflow.

        Context for analysis:
        - Skills and Expertise Entry values (content text) typically display about 44 characters per line before wrapping
        - Skills and Expertise Entry titles typically display about 28 characters per line before wrapping
        - Each entry starts on its own line

        Instructions:
        1. Look at the Education section in the resume image
        2. Check if any text appears to be cut off at the bottom of the page. There should be a minimum of a 1/4-inch margin above the page edge.
        3. Look for any visual indicators of content overflow (text running beyond boundaries, partial lines, etc.)
        4. Count approximately how many lines of text appear in the Skills and Expertise section must be removed to prevent the education section from extending off the bottom of the page.

        RESPONSE FORMAT:
        You must respond with a valid JSON object:
        {
          "contentsFit": true_or_false,
          "overflow_line_count": number_of_overflowing_lines
        }

        - Set contentsFit to true if all content fits properly within the page boundaries
        - Set contentsFit to false if there appears to be text overflow or cut-off content
        - Set overflow_line_count to the estimated number of lines in Skils and Expertise that must be removed to allow the content to fit on the page with a 0.25-inch margin
        - Do not include any text outside the JSON object
        """
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
