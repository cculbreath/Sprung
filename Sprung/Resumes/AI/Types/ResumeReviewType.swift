// Sprung/AI/Models/ResumeReviewType.swift
import Foundation
import PDFKit
import AppKit
import SwiftUI
/// Types of resume review operations available
enum ResumeReviewType: String, CaseIterable, Identifiable {
    case suggestChanges = "Suggest Resume Fields to Change"
    case assessQuality = "Assess Overall Resume Quality"
    case assessFit = "Assess Applicant Fit for Job Position"
    case fixOverflow = "Fix Overflow 'Skills & Expertise'"
    case reorderSkills = "Reorder 'Skills & Experience'"
    case custom = "Custom"
    var id: String { rawValue }
    /// Returns the prompt template for this review type
    /// Note: The prompt for fixOverflow will be handled more dynamically by ResumeReviewService
    /// due to its iterative nature and inclusion of image data.
    func promptTemplate() -> String {
        switch self {
        case .assessQuality:
            let contextHeader = ReviewPromptBuilder.buildContextHeader(
                jobPosition: "{jobPosition}",
                companyName: "{companyName}",
                additionalInfo: [
                    "• Full job description is included below.",
                    "• A draft of the applicant's resume follows the job description."
                ],
                includeImage: true
            )

            let sections = [
                (title: "Job Description", placeholder: "jobDescription"),
                (title: "Resume Draft", placeholder: "resumeText")
            ]

            return ReviewPromptBuilder.buildAssessmentPrompt(
                contextHeader: contextHeader,
                sections: sections,
                taskIntro: "You are an expert hiring manager and resume coach.",
                strengthsLabel: "Strengths",
                improvementsLabel: "Areas to Improve",
                ratingLabel: "Score",
                assessmentItems: [
                    "Evaluate the overall quality and professionalism of the resume **for this particular role**.",
                    "Provide exactly 3 key strengths (bullet list).",
                    "Provide exactly 3 concrete, actionable improvements (bullet list).",
                    "Give the resume an **overall score from 1-10** for readiness to submit."
                ],
                outputHeader: "### Overall Assessment (Score: <1-10>)",
                closingNote: "Keep the tone encouraging yet direct. Use concise, professional language."
            )

        case .assessFit:
            return ReviewPromptBuilder.buildFitAnalysisPrompt(
                jobPosition: "{jobPosition}",
                companyName: "{companyName}",
                includeImage: true
            )

        case .suggestChanges:
            return ReviewPromptBuilder.buildChangeSuggestionPrompt(
                jobPosition: "{jobPosition}",
                companyName: "{companyName}",
                sections: [
                    (title: "Job Description", placeholder: "jobDescription"),
                    (title: "Resume Draft", placeholder: "resumeText"),
                    (title: "Background Docs", placeholder: "backgroundDocs")
                ],
                additionalInfo: [
                    "• Job description is supplied below.",
                    "• Current resume draft follows.",
                    "• Additional background docs (if any) are appended at the end."
                ],
                instructions: """
                Identify resume sections (titles, bullet points, skill headings, summarized achievements, etc.) that should be **revised or strengthened** to maximise impact for this role.
                For each suggested change give:
                • The current text (quote succinctly)
                • The rationale for change (1-2 sentences)
                • A concise rewritten version (max 40 words)
                Output as a markdown table with columns: *Section*, *Why change?*, *Suggested Rewrite*.
                """
            )

        case .fixOverflow:
            return ReviewPromptBuilder.buildSimplePrompt(
                instruction: "The 'Skills and Expertise' section of the resume is overflowing. Please adjust the content to fit."
            )

        case .reorderSkills:
            let contextHeader = ReviewPromptBuilder.buildContextHeader(
                jobPosition: "{jobPosition}",
                companyName: "{companyName}",
                additionalInfo: [
                    "• Full job description is included below.",
                    "• A draft of the applicant's resume follows the job description."
                ],
                includeImage: true
            )

            let sections = [
                (title: "Job Description", placeholder: "jobDescription"),
                (title: "Resume Draft", placeholder: "resumeText")
            ]

            var components = [contextHeader]
            for section in sections {
                components.append(ReviewPromptBuilder.buildSection(title: section.title, placeholder: section.placeholder))
            }

            components.append(ReviewPromptBuilder.buildTask(instructions: """
            You are an expert resume consultant specializing in strategic skills presentation.
            1. Review the 'Skills & Experience' section of the resume.
            2. Analyze the job description to identify the most valuable and relevant skills.
            3. Recommend a reordering of the skills to prioritize those most relevant to the job.
            4. List the skills in the recommended order (most relevant first).
            Output format (markdown):
            ### Skills Reordering Recommendation
            **Current Skills Order**
            <List the current skills in their existing order>
            **Recommended Skills Order**
            <List the skills in recommended order with the most relevant first>
            **Rationale**
            <Brief explanation of the recommended changes and how they align with the job requirements>
            """))

            return components.joined(separator: "\n")

        case .custom:
            return ReviewPromptBuilder.emptyCustomPrompt()
        }
    }
}
/// Options to include in a custom resume review
struct CustomReviewOptions: Equatable {
    var includeJobListing: Bool = true
    var includeResumeText: Bool = true
    var includeResumeImage: Bool = true
    var customPrompt: String = ""
}
