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
            return """
            Context:
            ────────────────────────────────────────────
            • Applicant is applying for **{jobPosition}** at **{companyName}**.
            • Full job description is included below.
            • The finished application packet (cover letter and resume) follows.
            {includeImage}

            Job Description
            ----------------
            {jobDescription}

            Cover Letter
            ------------
            {coverLetterText}

            Resume
            ------
            {resumeText}

            Task:
            You are a seasoned recruiter. Carefully evaluate the overall quality and persuasiveness of this application.
            1. Provide **exactly three strengths** that make the candidate stand out.
            2. Provide **exactly three improvements** the candidate should make before submitting.
            3. Rate the likelihood of obtaining an interview on a **scale of 1-10** and explain the rating. The rating should reflect the current state of the application materials, as if the materials were submitted as-is without revision. Typographical errors or other amateur blunders are likely disqualifying and applications with these issues should not be awarded scores greater than 5.

            Output format (markdown):
            ### Overall Assessment (Interview Likelihood: <1-10>)

            **Strengths**
            • …
            • …
            • …

            **Improvements**
            • …
            • …
            • …
            """

        case .custom:
            return "" // will be built dynamically
        }
    }
}

/// Options for custom application review prompts
struct CustomApplicationReviewOptions: Equatable {
    var includeCoverLetter: Bool = true
    var includeResumeText: Bool = true
    var includeResumeImage: Bool = true
    var includeBackgroundDocs: Bool = false
    var selectedCoverLetter: CoverLetter? = nil
    var customPrompt: String = ""
}
