//
//  ApplicationReviewType.swift
//  Sprung
//
import Foundation
import PDFKit
import AppKit
import SwiftUI
/// Types of application-packet review operations
enum ApplicationReviewType: String, CaseIterable, Identifiable {
    /// Comprehensive quality / interview-prospect assessment
    case assessQuality = "Assess Application Quality"
    /// Build your own prompt
    case custom = "Custom"
    var id: String { rawValue }
    /// Prompt template for each operation
    func promptTemplate() -> String {
        switch self {
        case .assessQuality:
            let contextHeader = ReviewPromptBuilder.buildContextHeader(
                jobPosition: "{jobPosition}",
                companyName: "{companyName}",
                additionalInfo: [
                    "• Full job description is included below.",
                    "• The finished application packet (cover letter and resume) follows."
                ],
                includeImage: true
            )

            let sections = [
                (title: "Job Description", placeholder: "jobDescription"),
                (title: "Cover Letter", placeholder: "coverLetterText"),
                (title: "Resume", placeholder: "resumeText")
            ]

            return ReviewPromptBuilder.buildAssessmentPrompt(
                contextHeader: contextHeader,
                sections: sections,
                taskIntro: "You are a seasoned recruiter. Carefully evaluate the overall quality and persuasiveness of this application.",
                strengthsLabel: "Strengths",
                improvementsLabel: "Improvements",
                ratingLabel: "Interview Likelihood",
                assessmentItems: [
                    "Provide **exactly three strengths** that make the candidate stand out.",
                    "Provide **exactly three improvements** the candidate should make before submitting.",
                    "Rate the likelihood of obtaining an interview on a **scale of 1-10** and explain the rating. The rating should reflect the current state of the application materials, as if the materials were submitted as-is without revision. Typographical errors or other amateur blunders are likely disqualifying and applications with these issues should not be awarded scores greater than 5."
                ],
                outputHeader: "### Overall Assessment (Interview Likelihood: <1-10>)"
            )

        case .custom:
            return ReviewPromptBuilder.emptyCustomPrompt()
        }
    }
}
/// Options for custom application review prompts
struct CustomApplicationReviewOptions: Equatable {
    var includeCoverLetter: Bool = true
    var includeResumeText: Bool = true
    var includeResumeImage: Bool = true
    var includeBackgroundDocs: Bool = false
    var selectedCoverLetter: CoverLetter?
    var customPrompt: String = ""
}
