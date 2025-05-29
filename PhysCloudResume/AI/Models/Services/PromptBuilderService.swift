//
//  PromptBuilderService.swift
//  PhysCloudResume
//
//  Created by Team on 5/13/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Service to build prompts for different resume review types
class PromptBuilderService {
    /// Shared instance of the service
    static let shared = PromptBuilderService()
    
    private init() {}
    
    /// Builds an AI prompt for the given review type and resume
    /// - Parameters:
    ///   - reviewType: The type of review to perform
    ///   - resume: The resume to review
    ///   - includeImage: Whether to include image reference in the prompt
    ///   - customOptions: Optional custom review options
    /// - Returns: A formatted prompt string
    func buildPrompt(
        reviewType: ResumeReviewType,
        resume: Resume,
        includeImage: Bool,
        customOptions: CustomReviewOptions? = nil
    ) -> String {
        guard let jobApp = resume.jobApp else {
            return "Error: No job application associated with this resume."
        }

        var prompt = reviewType.promptTemplate()

        if reviewType == .custom, let options = customOptions {
            prompt = buildCustomPrompt(options: options)
        }

        prompt = prompt.replacingOccurrences(of: "{jobPosition}", with: jobApp.jobPosition)
        prompt = prompt.replacingOccurrences(of: "{companyName}", with: jobApp.companyName)
        prompt = prompt.replacingOccurrences(of: "{jobDescription}", with: jobApp.jobDescription)
        prompt = prompt.replacingOccurrences(of: "{resumeText}", with: resume.textRes)

        let backgroundDocs = resume.enabledSources.map { "\($0.name):\n\($0.content)\n\n" }.joined()
        prompt = prompt.replacingOccurrences(of: "{backgroundDocs}", with: backgroundDocs)

        let imagePlaceholder = includeImage ? "I've also attached an image for visual context." : ""
        prompt = prompt.replacingOccurrences(of: "{includeImage}", with: imagePlaceholder)

        return prompt
    }

    /// Builds a prompt for a custom review type
    /// - Parameter options: The custom review options
    /// - Returns: A formatted prompt string
    private func buildCustomPrompt(options: CustomReviewOptions) -> String {
        var sections: [String] = []
        if options.includeJobListing {
            sections.append("""
            I am applying for this job opening:
            {jobPosition}, {companyName}.
            Job Description:
            {jobDescription}
            """)
        }
        if options.includeResumeText {
            sections.append("""
            Here is a draft of my current resume:
            {resumeText}
            """)
        }
        if options.includeResumeImage { // This just affects the {includeImage} placeholder
            sections.append("{includeImage}")
        }
        sections.append(options.customPrompt)
        return sections.joined(separator: "\n\n")
    }
    
    /// Builds a specialized prompt for the 'fixFits' feature
    /// - Parameters:
    ///   - skillsJsonString: JSON string representation of skills
    ///   - allowEntityMerge: Whether to allow merging of redundant entries
    /// - Returns: A formatted prompt string
    func buildFixFitsPrompt(skillsJsonString: String, allowEntityMerge: Bool = false) -> String {
        let mergeInstructions = allowEntityMerge ? """
        
        ENTITY MERGE OPTION:
        You are allowed to merge two redundant or conceptually overlapping skill entries if it will help with fit and improve the resume's overall strength. When merging:
        - Each skill entry in the JSON contains: id, title, description, original_title, and original_description
        - Only merge skill entries that are truly redundant or where combining them creates a stronger, more comprehensive statement
        - Combine the best elements of both entries into a single, more impactful skill entry
        - The merged entry should preserve all unique aspects of both original entries
        - Only ONE merge operation is allowed per request
        - If you perform a merge, include a "merge_operation" object in your response with:
          - "skill_to_keep_id": The ID of the skill entry you want to keep
          - "skill_to_delete_id": The ID of the skill entry you want to delete
          - "merged_title": The combined skill title
          - "merged_description": The combined skill description
          - "merge_reason": A brief explanation of why these entries were merged
        """ : ""
        
        return """
        You are an expert resume editor. The 'Skills and Expertise' section in the attached resume image is overflowing. Please revise the content of this section to fit the available space without sacrificing its impact. Prioritize shortening entries that are only slightly too long (e.g., a few words on the last line). Ensure revised entries remain strong and relevant to the job application.

        IMPORTANT CONSTRAINTS:
        1. DO NOT use non-standard abbreviations or acronyms that aren't widely recognized in the industry.
        2. DO NOT truncate words to make them non-words (e.g., don't change "development" to "devt" or "devlpmnt").
        3. DO NOT create new terminology that isn't standard in the field.
        4. Only use standard, professionally accepted abbreviations (e.g., "MS" for Microsoft, "UI/UX" for User Interface/User Experience).
        5. Focus on rewording and condensing phrases to be more concise rather than abbreviating individual words.
        6. Maintain consistent grammar and professional language throughout.
        7. Avoid exaggerating or misrepresenting the applicant's actual experience level.
        8. When significant reductions are needed, balance edits across multiple entries rather than drastically shortening just one or two entries while leaving others at full length.
        9. Apply a consistent editing approach across similar types of entries.
        10. Do not shorten entries more than necessary to resolve the overflow.

        The current skills and expertise content is provided as a JSON array of nodes:

        \(skillsJsonString)

        Respond *only* with a JSON object adhering to the schema provided in the API request's 'response_format.schema' parameter. For each skill in your response, provide 'id', 'new_title' (if changed), 'new_description' (if changed), 'original_title', and 'original_description'. If you don't change a title or description, omit the corresponding 'new_' field.
        """
    }
    
    /// Builds a specialized prompt for the 'contentsFit' feature
    /// - Returns: A formatted prompt string
    func buildContentsFitPrompt() -> String {
        return """
        You are an expert document layout analyzer. Examine the attached resume image, specifically the 'Skills and Expertise' section (labeled with that header).
        
        Your task is to determine if this section fits properly and estimate any overflow.
        
        Context for analysis:
        - Entry values (content text) typically display about 44 characters per line before wrapping
        - Entry titles typically display about 28 characters per line before wrapping
        - Each entry starts on its own line
        
        Key things to analyze:
        1. Does any text extend beyond the Skills section's boundaries?
        2. Is there any overlap between the Skills section and the Education section below it?
        3. How many text lines (if any) are overflowing or overlapping?
        4. Is there a clean margin between the bottom of the Skills section and whatever comes after it?
        
        For the overflow_line_count estimation:
        - Count each line of text that visibly extends beyond the intended section boundary
        - Count lines that overlap with content below (even if text doesn't extend past boundaries)
        - Use 0 if content fits properly OR if bounding boxes overlap but no actual text lines overflow
        - Be conservative in your estimate - it's better to underestimate than overestimate
        
        Examples:
        - Content fits perfectly: {"contentsFit": true, "overflow_line_count": 0}
        - Minor overlap, no text overflow: {"contentsFit": false, "overflow_line_count": 0}
        - 2 lines of text clearly overflow: {"contentsFit": false, "overflow_line_count": 2}
        - Significant overflow, about 3-4 lines: {"contentsFit": false, "overflow_line_count": 4}
        
        IMPORTANT: Respond ONLY with the JSON structure specified in the API request's 'response_format.schema' parameter and NOTHING ELSE. Your ENTIRE response must be ONLY the JSON object. This is critical for automated processing and will be validated on the server side against the schema.
        """
    }
    
    /// Builds a specialized prompt for the 'fixFits' feature for Grok models (text-only)
    /// - Parameters:
    ///   - skillsJsonString: JSON string representation of skills
    ///   - overflowLineCount: Number of lines that are overflowing (0 if just touching boundaries)
    ///   - allowEntityMerge: Whether to allow merging of redundant entries
    /// - Returns: A formatted prompt string for Grok that doesn't require image analysis
    func buildGrokFixFitsPrompt(skillsJsonString: String, overflowLineCount: Int = 0, allowEntityMerge: Bool = false) -> String {
        let overflowGuidance = overflowLineCount > 0 
            ? "Visual analysis indicates approximately \(overflowLineCount) lines of text are overflowing the intended space. Focus your editing efforts on reducing content by roughly this amount."
            : "Visual analysis indicates the content boundaries are overlapping but no significant text overflow. Make minimal adjustments to ensure clean spacing."
        
        let mergeInstructions = allowEntityMerge ? """
        
        ENTITY MERGE OPTION:
        You are allowed to merge two redundant or conceptually overlapping skill entries if it will help with fit and improve the resume's overall strength. When merging:
        - Each skill entry in the JSON contains: id, title, description, original_title, and original_description
        - Only merge skill entries that are truly redundant or where combining them creates a stronger, more comprehensive statement
        - Combine the best elements of both entries into a single, more impactful skill entry
        - The merged entry should preserve all unique aspects of both original entries
        - Only ONE merge operation is allowed per request
        - If you perform a merge, include a "merge_operation" object in your response with:
          - "skill_to_keep_id": The ID of the skill entry you want to keep
          - "skill_to_delete_id": The ID of the skill entry you want to delete
          - "merged_title": The combined skill title
          - "merged_description": The combined skill description
          - "merge_reason": A brief explanation of why these entries were merged
        """ : ""
        
        return """
        You are an expert resume editor. It has been determined that the text column produced by these data nodes is too long for the available space. Please reduce the length of the text, doing your best to preserve all meaning while avoiding awkward or uncommon abbreviations or truncation. Pay special attention to entries that are longer than the others. 

        \(overflowGuidance)

        At the rendered font size that the "value" field is rendered, approximately 44 characters can fit on a single line. Use this information to implement changes that maximize the content per line while minimizing the number of lines overall. Each node "value" starts on its own line. A entry's title can accommodate approximately 28 characters. Try to keep all titles to no more than one line.

        IMPORTANT CONSTRAINTS:
        1. DO NOT use non-standard abbreviations or acronyms that aren't widely recognized in the industry.
        2. DO NOT truncate words to make them non-words (e.g., don't change "development" to "devt" or "devlpmnt").
        3. DO NOT create new terminology that isn't standard in the field.
        4. Only use standard, professionally accepted abbreviations (e.g., "MS" for Microsoft, "UI/UX" for User Interface/User Experience).
        5. Focus on rewording and condensing phrases to be more concise rather than abbreviating individual words.
        6. Maintain consistent grammar and professional language throughout.
        7. Avoid exaggerating or misrepresenting the applicant's actual experience level.
        8. When significant reductions are needed, balance edits across multiple entries rather than drastically shortening just one or two entries while leaving others at full length.
        9. Apply a consistent editing approach across similar types of entries.
        10. Do not shorten entries more than necessary to resolve the overflow.

        The current skills and expertise content is provided as a JSON array of nodes:

        \(skillsJsonString)

        Respond *only* with a JSON object adhering to the schema provided in the API request's 'response_format.schema' parameter. For each skill in your response, provide 'id', 'new_title' (if changed), 'new_description' (if changed), 'original_title', and 'original_description'. If you don't change a title or description, omit the corresponding 'new_' field.
        """
    }
    
    /// Builds a specialized prompt for the 'reorderSkills' feature
    /// - Parameters:
    ///   - skillsJsonString: JSON string representation of skills nodes
    ///   - jobDescription: The job description to optimize skills ordering for
    /// - Returns: A formatted prompt string
    func buildReorderSkillsPrompt(skillsJsonString: String, jobDescription: String) -> String {
        return """
        You are an expert resume editor specializing in optimizing skills presentation for specific job applications. I need you to analyze the Skills and Expertise section of a resume and recommend an optimal ordering of these skills to maximize impact for a specific job application.

        Job Description:
        \(jobDescription)

        Current Skills and Expertise (in JSON format - contains just name, id, and current order):
        \(skillsJsonString)

        Task: Analyze both the skills listed and the job description, then recommend an optimal ordering of these skills. Place the most relevant and impressive skills related to the job position at the top. Do not add or remove any skills, only reorder them.

        For each skill, include these fields exactly:
        - "id": String - The unchanged node ID
        - "originalValue": String - The original node name from the input
        - "newPosition": Integer - The suggested new position (0-based index)
        - "reasonForReordering": String - Brief explanation of why this position is appropriate

        Respond with a JSON object containing an array of skill objects under the 'reordered_skills_and_expertise' key, adhering to the schema provided in the API request's format parameter. The response will be validated on the server side against this schema.
        """
    }
}
