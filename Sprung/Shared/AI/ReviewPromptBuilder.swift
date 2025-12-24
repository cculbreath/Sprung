//
//  ReviewPromptBuilder.swift
//  Sprung
//
import Foundation

/// Shared utility for building structured review prompts with consistent formatting
struct ReviewPromptBuilder {

    // MARK: - Common Formatting

    /// Visual separator used in context sections
    static let separator = "────────────────────────────────────────────"

    /// Builds a context header with job information
    static func buildContextHeader(
        jobPosition: String,
        companyName: String,
        additionalInfo: [String] = [],
        includeImage: Bool = false
    ) -> String {
        var lines = [
            "Context:",
            separator,
            "• Applicant is applying for **\(jobPosition)** at **\(companyName)**."
        ]

        lines.append(contentsOf: additionalInfo)

        if includeImage {
            lines.append("{includeImage}")
        }

        return lines.joined(separator: "\n")
    }

    /// Builds a section header with content
    static func buildSection(title: String, placeholder: String) -> String {
        """
        \(title)
        \(String(repeating: "-", count: title.count))
        {\(placeholder)}
        """
    }

    /// Builds a task section with instructions
    static func buildTask(instructions: String) -> String {
        """
        Task:
        \(instructions)
        """
    }

    // MARK: - Assessment Prompts

    /// Builds a structured assessment prompt with strengths, improvements, and rating
    static func buildAssessmentPrompt(
        contextHeader: String,
        sections: [(title: String, placeholder: String)],
        taskIntro: String,
        strengthsLabel: String = "Strengths",
        improvementsLabel: String = "Areas to Improve",
        ratingLabel: String,
        assessmentItems: [String],
        outputHeader: String,
        additionalOutput: String = "",
        closingNote: String? = nil
    ) -> String {
        var components = [contextHeader]

        // Add all sections
        for section in sections {
            components.append(buildSection(title: section.title, placeholder: section.placeholder))
        }

        // Build task section
        var taskLines = [taskIntro]
        for (index, item) in assessmentItems.enumerated() {
            taskLines.append("\(index + 1). \(item)")
        }
        components.append(taskLines.joined(separator: "\n"))

        // Build output format
        var outputLines = [
            "Output format (markdown):",
            outputHeader,
            "**\(strengthsLabel)**",
            "• …",
            "• …",
            "• …",
            "**\(improvementsLabel)**",
            "• …",
            "• …",
            "• …"
        ]

        if !additionalOutput.isEmpty {
            outputLines.append(additionalOutput)
        }

        components.append(outputLines.joined(separator: "\n"))

        // Add closing note if provided
        if let note = closingNote {
            components.append(note)
        }

        return components.joined(separator: "\n")
    }

    /// Builds a fit analysis prompt (specific pattern for assessing match to role)
    static func buildFitAnalysisPrompt(
        jobPosition: String,
        companyName: String,
        includeImage: Bool = false
    ) -> String {
        let contextHeader = buildContextHeader(
            jobPosition: jobPosition,
            companyName: companyName,
            additionalInfo: ["• Job description and resume draft are provided."],
            includeImage: includeImage
        )

        let sections = [
            (title: "Job Description", placeholder: "jobDescription"),
            (title: "Resume Draft", placeholder: "resumeText")
        ]

        return buildAssessmentPrompt(
            contextHeader: contextHeader,
            sections: sections,
            taskIntro: "",
            strengthsLabel: "Strengths",
            improvementsLabel: "Gaps / Weaknesses",
            ratingLabel: "Fit Rating",
            assessmentItems: [
                "Assess how well the candidate's background matches the role requirements.",
                "List the **top 3 strengths** relevant to the job (bullet list).",
                "List the **top 3 gaps** or missing qualifications (bullet list).",
                "Give a **Fit Rating (1-10)** where 10 = perfect fit.",
                "State in one sentence whether it is worthwhile to apply."
            ],
            outputHeader: "### Fit Analysis (Rating: <1-10>)",
            additionalOutput: """
            **Recommendation**
            <One-sentence recommendation>
            """
        )
    }

    /// Builds a change suggestion prompt (table format for revisions)
    static func buildChangeSuggestionPrompt(
        jobPosition: String,
        companyName: String,
        sections: [(title: String, placeholder: String)],
        additionalInfo: [String] = [],
        instructions: String
    ) -> String {
        let contextHeader = buildContextHeader(
            jobPosition: jobPosition,
            companyName: companyName,
            additionalInfo: additionalInfo,
            includeImage: false
        )

        var components = [contextHeader]

        // Add all sections
        for section in sections {
            components.append(buildSection(title: section.title, placeholder: section.placeholder))
        }

        components.append(buildTask(instructions: instructions))

        return components.joined(separator: "\n")
    }

    // MARK: - Simple Prompts

    /// Builds a simple instruction-only prompt (for overflow fixes, etc.)
    static func buildSimplePrompt(instruction: String) -> String {
        instruction
    }

    /// Returns an empty string for custom prompts that will be built dynamically
    static func emptyCustomPrompt() -> String {
        ""
    }
}
