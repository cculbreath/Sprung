//
//  CoverLetterPrompts.swift
//  Sprung
//
//
import Foundation
enum CoverAiMode: String, Codable {
    case generate
    case revise
    case rewrite
    case none
}
enum CoverLetterPrompts {
    static var systemMessage = LLMMessage.text(
        role: .system,
        content: """
            You are an expert career advisor and professional writer specializing in crafting exceptional and memorable cover letters. \
            Your task is to create an extraordinarily well-written and memorable cover letter for a job application, based on the job listing and resume provided below. \
            The cover letter should be in plain text with no commentary or annotations. \
            IMPORTANT: Return ONLY the body content of the letter - do not include date, address, salutation (like 'Dear Hiring Manager'), signature, name, or contact information. \
            Your response should start immediately with the first paragraph of the letter body and end with the final paragraph. \
            The letter should use block-format paragraphs with no indentation, and just a single new line at the end of each paragraph. \
            Do not add a blank line between paragraphs.
            """
    )
    @MainActor
    static func generate(
        coverLetter: CoverLetter,
        resume: Resume,
        mode: CoverAiMode,
        applicant: Applicant,
        writersVoice: String,
        customFeedbackString: String? = ""
    ) -> String {
        let app = coverLetter.jobApp
        var prompt = ""
        switch mode {
        case .generate:
            prompt = """
            You are an expert career advisor and professional writer specializing in crafting exceptional and memorable cover letters. \
            Your task is to create an extraordinarily well-written and memorable cover letter for \(applicant.name)'s application to be hired as a \(app?.jobPosition ?? "") at \(app?.companyName ?? "").
            IMPORTANT: Your response must contain ONLY the body text of the cover letter. Do not include date, salutation (Dear Hiring Manager), closing (Best Regards), signature, name, or contact information. \
            Start immediately with the first paragraph and end with the final paragraph. These elements will be added automatically by the system.
            **Instructions:**
            - **Personalization:** Tailor the cover letter specifically to the job listing at \(app?.companyName ?? ""), aligning \(applicant.name)'s skills and experiences with the job requirements.
            - **Highlight Strengths:** Emphasize the most relevant qualifications, achievements, and experiences from \(applicant.name)'s résumé that make them an ideal fit for the position.
            - **Professional Tone:** Maintain a professional and engaging tone throughout the letter.
            - **Memorable Impact:** Craft the letter to leave a lasting impression on the reader, making it stand out among other applications.
            - **Single Line Spacing:** Use single line spacing with proper paragraph breaks.
            - **Format:** The letter should use block-format paragraphs with no indentation, and just a single new line at the end of each paragraph. \
            Do not add extra blank lines between paragraphs.
            \(applicant.name)'s contact information:
            \(applicant.name)
            \(applicant.address)
            \(applicant.city), \(applicant.state) \(applicant.zip)
            \(applicant.email)
            \(applicant.websites)
            **Full Job Listing:**
            \(app?.jobListingString ?? "")
            **Text Version of Résumé to be Submitted with Application:**
            \(resume.textResume)
            \(applicant.name) has also included writing samples from cover letters they wrote for earlier applications that they are particularly satisfied with. \
            These samples demonstrate \(applicant.name)'s preferred writing style and voice that should be emulated:
            **WRITING SAMPLES TO EMULATE:**
            \(writersVoice)
            """
        case .revise:
            prompt = """
                Upon reading your latest draft, \(applicant.name) has provided the following feedback:
                    \(customFeedbackString ?? "no feedback provided")
            requested that you prepare a revised draft that improves upon the original while incorporating \(applicant.name)'s feedback. \
            Your response should only include the plain full text the revised letter draft without any markdown formatting or additonal explanations or reasoning.
            """
        case .rewrite:
            prompt = """
                My initial draft of a cover letter to accompany my application to be hired as a  \(app?.jobPosition ?? "") at \(app?.companyName ?? "") is included below.
                \(coverLetter.editorPrompt.rawValue)
            Cover Letter initial draft:
            \(coverLetter.content)
            """
            // For mimic revisions, add the writing samples context
            if coverLetter.editorPrompt == .mimic {
                prompt = """
                    \(applicant.name) has written an initial draft of a cover letter to accompany their application to be hired as a \(app?.jobPosition ?? "") at \(app?.companyName ?? "").
                    \(applicant.name) has also included writing samples from cover letters they wrote for earlier applications that they are particularly satisfied with. \
                    These samples demonstrate \(applicant.name)'s preferred writing style and voice that should be emulated:
                    **WRITING SAMPLES TO EMULATE:**
                    \(writersVoice)
                    **REVISION INSTRUCTIONS:**
                    \(coverLetter.editorPrompt.rawValue)
                    **COVER LETTER INITIAL DRAFT:**
                    \(coverLetter.content)
                    """
            }
        case .none:
            prompt = "none"
        }
        return prompt
    }
    enum EditorPrompts: String, Codable, CaseIterable {
        case improve = """
            Please carefully read the draft and indentify at least three ways the content and quality of the writing can be improved. \
            Provde a new draft that incorporates the identified improvements.
            """
        case zinsser = """
            Carefully read the letter as a professional editor, specifically William Zinsser, incorporating the writing techniques and style he advocates in "On Writing Well." \
            Provide a new draft that incorporates Zinsser's edits to improve the quality of the writing.
            """
        case mimic = """
            The draft provided does not align closely with the tone, style, or word choice demonstrated in the sample letters. \
            Please rewrite the draft to convincingly match the voice, structure, and nuanced feel of the samples. \
            Prioritize consistency in tone and linguistic choices, ensuring the revised draft mirrors the fluidity and authenticity of the original style.
            """
        case custom = "Please provide a revised draft of the provided cover letter incorporating the following feedback: "
    }
}
/// Represents the human-readable revision operation applied to a cover letter
enum RevisionOperation: String, Codable {
    case improve = "Improve"
    case zinsser = "Zinsser"
    case mimic = "Mimic"
    case custom = "Custom"
}
extension CoverLetterPrompts.EditorPrompts {
    /// Maps an EditorPrompt case to its corresponding revision operation
    var operation: RevisionOperation {
        switch self {
        case .improve: return .improve
        case .zinsser: return .zinsser
        case .mimic: return .mimic
        case .custom: return .custom
        }
    }
}
