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
    /// - Returns: A formatted prompt string
    func buildFixFitsPrompt(skillsJsonString: String) -> String {
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

        Respond *only* with a JSON object adhering to the schema provided in the API request's 'response_format.schema' parameter. Each node in your response must include the original 'id', 'originalValue', 'isTitleNode', and 'treePath' fields exactly as they were provided in the input. Provide your suggested change in the 'newValue' field.
        """
    }
    
    /// Builds a specialized prompt for the 'contentsFit' feature
    /// - Returns: A formatted prompt string
    func buildContentsFitPrompt() -> String {
        return """
        You are an expert document layout analyzer. Examine the attached resume image, specifically the 'Skills and Expertise' section (labeled with that header).
        
        Your task is to determine if this section fits properly without overflowing or overlapping with other content.
        
        Key things to check:
        1. Is there any text that extends beyond the section's boundaries?
        2. Is there any overlap between the Skills section and the Education section below it?
        3. Is there a small, clean margin between the bottom of the Skills section and whatever comes after it?
        
        A properly fitting section has all text fully contained within its boundaries and has a visible margin to the section below it.
        
        IMPORTANT: Respond ONLY with the JSON structure specified in the API request's 'response_format.schema' parameter and NOTHING ELSE:
        
        {"contentsFit": true}  - if everything fits properly
        {"contentsFit": false} - if there is any overflow or text cuts off
        
        DO NOT include any explanation, analysis, or additional text. Your ENTIRE response must be ONLY the JSON object. This is critical for automated processing and will be validated on the server side against the schema.
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
