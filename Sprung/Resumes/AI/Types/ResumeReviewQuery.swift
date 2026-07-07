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
    ///   - knowledgeCards: Background knowledge cards to include, read fresh from the store
    ///   - customOptions: Optional custom review options
    /// - Returns: The complete prompt string
    func buildReviewPrompt(
        reviewType: ResumeReviewType,
        resume: Resume,
        includeImage: Bool,
        knowledgeCards: [KnowledgeCard],
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
        // Background docs: knowledge cards read fresh from the store
        let bgDocs = knowledgeCards.map { "\($0.title):\n\($0.narrative)\n\n" }.joined()
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
}
