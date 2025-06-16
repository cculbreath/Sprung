//
//  ApplicationReviewQuery.swift
//  PhysCloudResume
//
//  Created by Claude on 6/5/25.
//

import Foundation

/// Centralized prompt management for application review operations
/// Follows the architecture pattern from ResumeQuery.swift and CoverLetterQuery.swift
@Observable class ApplicationReviewQuery {
    
    // MARK: - Main Review Prompt Building
    
    /// Build the main application review prompt
    /// - Parameters:
    ///   - reviewType: The type of review to perform
    ///   - jobApp: The job application context
    ///   - resume: The resume to review
    ///   - coverLetter: The cover letter to review (optional)
    ///   - includeImage: Whether image analysis is available
    ///   - customOptions: Optional custom review options
    /// - Returns: The complete prompt string
    func buildReviewPrompt(
        reviewType: ApplicationReviewType,
        jobApp: JobApp,
        resume: Resume,
        coverLetter: CoverLetter?,
        includeImage: Bool,
        customOptions: CustomApplicationReviewOptions? = nil
    ) -> String {
        var prompt = reviewType.promptTemplate()

        // Handle custom build if necessary
        if reviewType == .custom, let opt = customOptions {
            prompt = buildCustomPrompt(options: opt)
        }

        prompt = prompt.replacingOccurrences(of: "{jobPosition}", with: jobApp.jobPosition)
        prompt = prompt.replacingOccurrences(of: "{companyName}", with: jobApp.companyName)
        prompt = prompt.replacingOccurrences(of: "{jobDescription}", with: jobApp.jobDescription)

        // Cover letter text replacement
        let coverText = coverLetter?.content ?? ""
        prompt = prompt.replacingOccurrences(of: "{coverLetterText}", with: coverText)

        // Resume text replacement
        let resumeText = resume.textRes.isEmpty ? (resume.model?.renderedResumeText ?? "") : resume.textRes
        prompt = prompt.replacingOccurrences(of: "{resumeText}", with: resumeText)

        // Background docs placeholder
        let bgDocs = resume.enabledSources.map { "\($0.name):\n\($0.content)\n\n" }.joined()
        prompt = prompt.replacingOccurrences(of: "{backgroundDocs}", with: bgDocs)

        // Include image sentence
        let imageText = includeImage ? "I've also attached an image so you can assess its overall professionalism and design." : ""
        prompt = prompt.replacingOccurrences(of: "{includeImage}", with: imageText)

        return prompt
    }
    
    /// Build the system prompt for application review
    /// - Returns: The system prompt that establishes the AI's role
    func systemPrompt() -> String {
        return "You are an expert recruiter reviewing job application packets."
    }
    
    // MARK: - Custom Prompt Building
    
    /// Build custom prompt from options
    /// - Parameter options: The custom review options
    /// - Returns: Complete custom prompt string
    private func buildCustomPrompt(options: CustomApplicationReviewOptions) -> String {
        var segments: [String] = []

        Logger.debug("🔧 [ApplicationReview] Building custom prompt")
        Logger.debug("🔧 [ApplicationReview] Include cover letter: \(options.includeCoverLetter)")
        Logger.debug("🔧 [ApplicationReview] Include resume text: \(options.includeResumeText)")
        Logger.debug("🔧 [ApplicationReview] Include resume image: \(options.includeResumeImage)")
        Logger.debug("🔧 [ApplicationReview] Include background docs: \(options.includeBackgroundDocs)")
        Logger.debug("🔧 [ApplicationReview] Custom prompt length: \(options.customPrompt.count)")

        if options.includeCoverLetter {
            segments.append("""
            Cover Letter
            ------------
            {coverLetterText}
            """)
        }

        if options.includeResumeText {
            segments.append("""
            Resume
            ------
            {resumeText}
            """)
        }

        if options.includeResumeImage {
            segments.append("{includeImage}")
        }

        if options.includeBackgroundDocs {
            segments.append("""
            Background Docs
            ---------------
            {backgroundDocs}
            """)
        }

        // Add custom prompt or a default if empty
        let finalPrompt = options.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalPrompt.isEmpty {
            Logger.warning("🔧 [ApplicationReview] Custom prompt is empty, using default")
            segments.append("Please review the above materials and provide your analysis.")
        } else {
            segments.append(finalPrompt)
        }
        
        let result = segments.joined(separator: "\n\n")
        Logger.debug("🔧 [ApplicationReview] Custom prompt built, total length: \(result.count)")
        return result
    }
    
    // MARK: - Console Print Friendly Methods
    
    /// Creates a console-friendly version of the prompt with truncated long strings
    func consoleFriendlyPrompt(_ fullPrompt: String) -> String {
        var truncatedPrompt = fullPrompt
        
        // Get background docs for truncation
        let bgDocs = fullPrompt.range(of: "{backgroundDocs}").map { _ in "[background docs content]" } ?? ""
        if !bgDocs.isEmpty {
            let truncatedBgDocs = truncateString(bgDocs, maxLength: 200)
            truncatedPrompt = truncatedPrompt.replacingOccurrences(of: "{backgroundDocs}", with: truncatedBgDocs)
        }
        
        // Truncate resume text if present
        if truncatedPrompt.contains("{resumeText}") {
            let truncatedResumeText = "[Resume text truncated...]"
            truncatedPrompt = truncatedPrompt.replacingOccurrences(of: "{resumeText}", with: truncatedResumeText)
        }
        
        // Truncate cover letter text if present
        if truncatedPrompt.contains("{coverLetterText}") {
            let truncatedCoverLetter = "[Cover letter text truncated...]"
            truncatedPrompt = truncatedPrompt.replacingOccurrences(of: "{coverLetterText}", with: truncatedCoverLetter)
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