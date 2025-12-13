//
//  DocumentExtractionPrompts.swift
//  Sprung
//
//  Centralized prompts for document extraction and summarization.
//  Used by GoogleAIService for PDF/document text extraction and summary generation.
//

import Foundation

enum DocumentExtractionPrompts {

    // MARK: - Extraction Prompts

    /// Default prompt for PDF text extraction.
    /// Instructs the model to produce a detailed, structured transcription
    /// that preserves the original content for downstream processing.
    static let defaultExtractionPrompt: String = """
        Extract and transcribe the content of this professional document to support resume and cover letter drafting.

        CRITICAL INSTRUCTION: The output MUST be a highly detailed, structured transcription that errs heavily on the side of inclusion, not abridgement. This output will serve as the sole source for downstream tasks; no material information should be omitted or summarized aggressively. Original writing should preserve the author's voice and be a verbatim transcription by default.

        Output format: Provide a thorough, structured transcription in markdown.

        Content handling rules:
        - Every page of the original document should be referenced in the transcript. If you reference a range of pages, keep the span of the reference small, and use sparingly.
        - **Verbatim Transcription Mandate:** Any major narrative essay, standalone statement, or comprehensive project description MUST be transcribed **VERBATIM**, preserving all original paragraph structure, subheadings, and formatting.
        - Quantitative information may be consolidated into summarizing values as long as job-application relevant quantities are well preserved and fully represented.
        - Diagrams, figures, and visual content: Describe what is shown AND what it demonstrates about the applicant's work or capabilities.

        Respond with a JSON object containing:
        - "title": A concise, descriptive title for this document
        - "content": The comprehensive transcription in markdown format (aim for thoroughness over brevity)

        Example: {"title": "John Smith Resume", "content": "# Summary\\n\\nContent here..."}
        """

    // MARK: - Summarization Prompts

    /// Prompt for document summarization.
    /// Generates structured JSON output with summary, document type, metadata.
    /// Used to create lightweight context for the main LLM coordinator.
    static func summaryPrompt(filename: String, content: String) -> String {
        """
        Analyze this document and provide a structured summary for job application context.
        Document filename: \(filename)

        --- DOCUMENT CONTENT ---
        \(content.prefix(100000))
        --- END DOCUMENT ---

        Output as JSON with this exact structure:
        {
          "document_type": "resume|performance_review|project_doc|job_description|letter_of_recommendation|certificate|transcript|portfolio|other",
          "brief_description": "10-word max one-liner describing document content (e.g., 'Resume covering 5 years at tech startups')",
          "summary": "~500 word narrative summary covering: what the document contains, key information relevant to job applications, notable details that stand out",
          "time_period": "YYYY-YYYY" or null if not applicable,
          "companies": ["Company A", "Company B"],
          "roles": ["Role 1", "Role 2"],
          "skills": ["Swift", "Python", "Leadership"],
          "achievements": ["Led team of 5", "Shipped 3 products"],
          "relevance_hints": "Brief note about what types of knowledge cards this doc could support"
        }

        BRIEF DESCRIPTION: A quick glance identifier (max 10 words). Examples:
        - "Resume: Senior engineer at Acme Corp, 2019-2023"
        - "Performance review: Q4 2022 exceeds expectations rating"
        - "Project doc: Microservices migration architecture proposal"

        DOCUMENT TYPE GUIDANCE:
        - resume: A CV or resume document showing work history, education, and skills
        - performance_review: Employee performance evaluation, 360 feedback, or annual review
        - project_doc: Technical documentation, design docs, project reports, or presentations
        - job_description: Job posting, role description, or position requirements
        - letter_of_recommendation: Reference letter or recommendation
        - certificate: Professional certification, award, or credential
        - transcript: Academic transcript or course record
        - portfolio: Collection of work samples or project showcase
        - other: Document that doesn't fit the above categories

        SUMMARY GUIDELINES:
        - Be thorough - this summary is the ONLY context the main LLM coordinator will see
        - Include specific details: company names, job titles, dates, technologies, metrics
        - Extract quantitative achievements when available (e.g., "increased revenue by 40%")
        - Note leadership scope (team sizes, budget responsibility, geographic span)
        - Identify key technical skills and domain expertise
        - Preserve important quotes or specific phrases that capture accomplishments

        RELEVANCE HINTS:
        - Identify which knowledge card types this document could inform:
          - "job" cards: Work experience, roles, responsibilities
          - "skill" cards: Technical competencies, soft skills, domain expertise
          - "project" cards: Specific projects, initiatives, or accomplishments
        - Note any gaps or areas where additional documentation might be needed

        Return ONLY valid JSON. Do not include markdown code fences or explanatory text.
        """
    }
}
