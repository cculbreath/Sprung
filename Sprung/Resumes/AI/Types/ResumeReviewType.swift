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
    case custom = "Custom"
    var id: String { rawValue }
    /// Returns the prompt template for this review type
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
