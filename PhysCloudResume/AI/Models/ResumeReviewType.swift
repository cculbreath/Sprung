// PhysCloudResume/AI/Models/ResumeReviewType.swift

import Foundation

/// Types of resume review operations available
enum ResumeReviewType: String, CaseIterable, Identifiable {
    case suggestChanges = "Suggest Resume Fields to Change"
    case assessQuality = "Assess Overall Resume Quality"
    case assessFit = "Assess Fit for Job Position"
    case fixOverflow = "Fix Skills & Expertise Overflow" // New case
    case custom = "Custom"

    var id: String { rawValue }

    /// Returns the prompt template for this review type
    /// Note: The prompt for fixOverflow will be handled more dynamically by ResumeReviewService
    /// due to its iterative nature and inclusion of image data.
    func promptTemplate() -> String {
        switch self {
        case .assessQuality:
            // Enhanced prompt – asks for a structured, actionable answer in markdown
            return """
            Context:
            ────────────────────────────────────────────
            • Applicant is applying for **{jobPosition}** at **{companyName}**.
            • Full job description is included below.
            • A draft of the applicant’s resume follows the job description.
            {includeImage}

            Job Description
            ----------------
            {jobDescription}

            Resume Draft
            -------------
            {resumeText}

            Task:
            You are an expert hiring manager and resume coach.
            1. Evaluate the overall quality and professionalism of the resume **for this particular role**.
            2. Provide exactly 3 key strengths (bullet list).
            3. Provide exactly 3 concrete, actionable improvements (bullet list).
            4. Give the resume an **overall score from 1-10** for readiness to submit.

            Output format (markdown):
            ### Overall Assessment (Score: <1-10>)

            **Strengths**
            • …
            • …
            • …

            **Areas to Improve**
            • …
            • …
            • …

            Keep the tone encouraging yet direct. Use concise, professional language.
            """

        case .assessFit:
            return """
            Context:
            ────────────────────────────────────────────
            • Applicant wishes to apply for **{jobPosition}** at **{companyName}**.
            • Job description and resume draft are provided.
            {includeImage}

            Job Description
            ----------------
            {jobDescription}

            Resume Draft
            -------------
            {resumeText}

            Task:
            1. Assess how well the candidate’s background matches the role requirements.
            2. List the **top 3 strengths** relevant to the job (bullet list).
            3. List the **top 3 gaps** or missing qualifications (bullet list).
            4. Give a **Fit Rating (1-10)** where 10 = perfect fit.
            5. State in one sentence whether it is worthwhile to apply.

            Output format (markdown):
            ### Fit Analysis (Rating: <1-10>)
            **Strengths**
            • …
            • …
            • …

            **Gaps / Weaknesses**
            • …
            • …
            • …

            **Recommendation**
            <One-sentence recommendation>
            """

        case .suggestChanges:
            return """
            Context:
            ────────────────────────────────────────────
            • Target role: **{jobPosition}** at **{companyName}**.
            • Job description is supplied below.
            • Current resume draft follows.
            • Additional background docs (if any) are appended at the end.

            Job Description
            ----------------
            {jobDescription}

            Resume Draft
            -------------
            {resumeText}

            Background Docs
            ---------------
            {backgroundDocs}

            Task:
            Identify resume sections (titles, bullet points, skill headings, summarized achievements, etc.) that should be **revised or strengthened** to maximise impact for this role.

            For each suggested change give:
            • The current text (quote succinctly)
            • The rationale for change (1-2 sentences)
            • A concise rewritten version (max 40 words)

            Output as a markdown table with columns: *Section*, *Why change?*, *Suggested Rewrite*.
            """
        case .fixOverflow:
            // This prompt is more complex and will be constructed within ResumeReviewService
            // as it involves image data and iterative calls.
            // A base instruction could be:
            return "The 'Skills and Expertise' section of the resume is overflowing. Please adjust the content to fit."
            
        case .custom:
            // Custom prompt will be built dynamically; return empty string here.
            return ""
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
