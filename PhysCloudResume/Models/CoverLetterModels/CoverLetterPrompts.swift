//
//  CoverLetterPrompts.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/12/24.
//
import SwiftOpenAI

enum CoverAiMode: String, Codable {
  case generate
  case revise
  case rewrite
  case none

}
struct CoverLetterPrompts {

  static var systemMessage = ChatCompletionParameters.Message(
    role: .system,
    content: .text("You are an expert career advisor and professional writer specializing in crafting exceptional and memorable cover letters. Your task is to create an extraordinarily well-written and memorable cover letter for a job application, based on the job listing and resume provided below. The cover letter should be in plain text with no commentary or annotations—only the text of the letter itself."))

  static func generate(coverLetter: CoverLetter, resume: Resume, mode: CoverAiMode) -> String {
    let applicant = Applicant()
    let app = coverLetter.jobApp
    
    var prompt: String = ""
    switch mode {
    case .generate:
      prompt = """
        You are an expert career advisor and professional writer specializing in crafting exceptional and memorable cover letters. Your task is to create an extraordinarily well-written and memorable cover letter for \(applicant.name)'s application to be hired as a \(app?.job_position ?? "") at \(app?.company_name ?? ""). The cover letter should be in plain text with no commentary or annotations—only the text of the letter itself.

        **Instructions:**

        - **Personalization:** Tailor the cover letter specifically to the job listing at \(app?.company_name ?? ""), aligning \(applicant.name)'s skills and experiences with the job requirements.
        - **Highlight Strengths:** Emphasize the most relevant qualifications, achievements, and experiences from \(applicant.name)'s résumé that make them an ideal fit for the position.
        - **Professional Tone:** Maintain a professional and engaging tone throughout the letter.
        - **Memorable Impact:** Craft the letter to leave a lasting impression on the reader, making it stand out among other applications.
        - **Formatting:** Begin with a proper salutation and structure the letter in coherent paragraphs, concluding with a strong closing statement.

        \(applicant.name) has provided the following background information regarding their current job search that may be useful in composing the draft cover letter:
        \(applicant.name)'s contact information:
        \(applicant.name)
        \(applicant.address)
        \(applicant.city), \(applicant.state) \(applicant.zip)
        \(applicant.email)
        \(applicant.websites)
        
        Additional Background Facts:
        \(coverLetter.backgroundItemsString)

        **Full Job Listing:**

        \(app?.jobListingString ?? "")

        **Text Version of Résumé to be Submitted with Application:**

        \(resume.textRes)

        \(applicant.name) has also included a few samples of cover letters they wrote for earlier applications that they are particularly satisfied with. Use these writing samples as a guide to the writing style and voice of your cover letter draft:

        \(coverLetter.writingSamplesString)
        """
    case .revise:
      prompt = """
            [Messsage History]
            Upon reading your latest draft, \(applicant.name) has requested that you prepare a revised draft that incorporates each of the feedback items below:

                [cannedResponseString]
        """
    case .rewrite:
      prompt = """
            My initial draft of a cover letter to accompany my application to be hired as a  \(app?.job_position ?? "") at \(app?.company_name ?? "") is included below.
            \(coverLetter.editorPrompt)
        
        Cover Letter initial draft:
        \(coverLetter.content)

        """
      case .none:
        prompt = "none"
    }

    return prompt
  }
  enum EditorPrompts: String, Codable, CaseIterable {
    case improve =
      "Please carefully read the draft and indentify at least three ways the content and quality of the writing can be improved. Provde a new draft that incorporates the identified improvements."
    case zissner =
      "Carefully read the letter as a professional editor, specifically William Zissner incorporating the writing techniques and style he advocates in \"On Writing Well\" Provide a new draft that incorporates Zissner's edits to improve the quality of the writing. "
  }
}
