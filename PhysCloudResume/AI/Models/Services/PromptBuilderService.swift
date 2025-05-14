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
        You are an expert resume editor. The 'Skills and Expertise' section in the attached resume image is overflowing. Please revise the content of this section to fit the available space without sacrificing its impact. Prioritize shortening entries that are only slightly too long (e.g., a few words on the last line). Ensure revised entries remain strong and relevant to the job application. Do not shorten entries more than necessary to resolve the overflow and avoid overlapping with elements below. The current skills and expertise content is provided as a JSON array of nodes:

        \(skillsJsonString)

        Respond *only* with a JSON object adhering to the schema provided in the API request's 'text.format.schema' parameter. Each node in your response must include the original 'id', 'originalValue', 'isTitleNode', and 'treePath' fields exactly as they were provided in the input. Provide your suggested change in the 'newValue' field. Set 'valueChanged' to true if you made a change, false otherwise.
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
        
        Respond with a simple JSON containing a single boolean field called "contentsFit":
        
        If everything fits properly with no overflow: {"contentsFit": true}
        If there is any overflow or overlap: {"contentsFit": false}
        
        Ensure your response is ONLY this JSON object - no extra text or explanation.
        """
    }
}
