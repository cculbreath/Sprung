//
//  ResumeQuery.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/25/24.
//

import Foundation
import SwiftOpenAI

@Observable class ResumeApiQuery {
    static let revNodeArraySchema =
    JSONSchemaResponseFormat(
        name: "revNode_array_response",
        strict: true,
        schema: JSONSchema(
            type: .object,
            properties: ["revArray":JSONSchema(
        type: .array,
        items: JSONSchema(
            type: .object,
            properties: [
                "id": JSONSchema(
                    type: .integer,
                    description:
                        "The unique identifier for the revision"
                ),
                "oldValue": JSONSchema(
                    type: .string,
                    description:
                        "The original value before revision"),
                "newValue": JSONSchema(
                    type: .string,
                    description:
                        "The proposed new value after revision"),
                "valueChanged": JSONSchema(
                    type: .boolean,
                    description:
                        "Indicates if the value is changed by the proposed revision."
                ),
                "why": JSONSchema(
                    type: .string,
                    description:
                        "Explanation for the proposed revision. Note that an explanation is not required: set this value to a blank string if the reason is trivial or obvious."
                ),
            ]))]))

    let systemMessage = ChatCompletionParameters.Message(
        role: .system,
        content: .text(
            "You are an expert career coach with a specialization in crafting and refining technical resumes to optimize them for job applications. With extensive experience in helping candidates secure interviews at top companies, you understand the importance of aligning resume content with job descriptions and the subtleties of tailoring resumes to specific roles. \n\nYour task is to use the information provided—such as the candidate’s current resume, job listing details, and additional background resources—to customize and optimize the resume. You should mirror the language and specific skills mentioned in the job listing where appropriate, ensuring that the resume is tailored to meet the expectations of potential employers while staying true to the candidate’s actual skills and experiences. Your goal is to make the resume as compelling as possible for the target position, increasing the chances of the candidate being selected for an interview"
        ))


    let applicant: Applicant
    var queryString: String = ""
    let attentionGrab: Int = 2
    let res: Resume
    var backgroundDocs: String {
        let bgrefs = res.bgDocs
        if bgrefs.isEmpty {
            return ""
        } else {
            return bgrefs.map { $0.name + ":\n" + $0.content + "\n\n" }.joined()
        }

    }
    var resumeText: String {
        let sources = res.enabledSources
        if sources.isEmpty { return "" }

        return sources.first { $0.type == SourceType.resumeSource }?.content
            ?? ""
    }
    var resumeJson: String {
        let sources = res.enabledSources
        if sources.isEmpty {
            return ""
        }

        return sources.first { $0.type == SourceType.jsonSource }?.content ?? ""
    }
    var jobListing: String {
//        print(res.jobApp?.jobListingString ?? "")
        return res.jobApp?.jobListingString ?? ""
    }

    var updatableFieldsString: String {
        let exportDict = TreeNode.traverseAndExportNodes(node: res.rootNode)

        do {
            let updatableJsonData = try JSONSerialization.data(
                withJSONObject: exportDict, options: .prettyPrinted)
            return String(data: updatableJsonData, encoding: .utf8) ?? ""
        } catch {
            print("Error serializing JSON: \(error.localizedDescription)")
            return ""
        }
    }

    init(resume: Resume) {
        applicant = Applicant()  //To Do allow for general applicant name etc. (Needs UI)
        self.res = resume

    }
    var wholeResumeQueryString: String {
        var attentionGrabLanguage: String

        switch self.res.attentionGrab {
        case 0:
            attentionGrabLanguage = ""
        case 1:
            attentionGrabLanguage =
                "Make the résumé stand out by emphasizing key skills and experiences without going overboard."
        case 2:
            attentionGrabLanguage =
                "Ensure the résumé is memorable and attention-grabbing, while maintaining a focus on relevance and truthfulness."
        case 3:
            attentionGrabLanguage =
                "Make a strong impression with the résumé, prioritizing memorability and uniqueness, even if it pushes some boundaries."
        case 4:
            attentionGrabLanguage =
                "Make every effort to make this résumé memorable and attention-grabbing above all else. Making any sort of impression is more important than making a positive impression. Make this résumé something the recruiter is certain to remember, even if it pushes some boundaries."
        default:
            attentionGrabLanguage = ""
        }

        // Start building the prompt string
        let prompt = """
            Latest Résumé:
            \(resumeText)

            This is the most recent version of \(applicant.name)'s résumé, rendered in plain text. The résumé was generated from the following JSON data using a command-line utility and a Handlebars-based template. The utility also creates HTML and PDF versions.

            Résumé Source JSON:
            \(resumeJson)

            Goal:
            Our primary objective is to secure \(applicant.name) an interview for the following position:

            Job Listing:
            \(jobListing)

            Task:
            Starting with \(applicant.name)'s latest résumé, your task is to utilize the background resources provided below to customize the résumé. The goal is to ensure it is finely tailored to the job listing.

            - **Do Not** fabricate experience.
            - **Do** highlight and frame the skills and experiences in a way that is most relevant and compelling for the position.
            - **Do** mirror the specific language and skills mentioned in the job listing, as long as they are consistent with \(applicant.name)'s actual skills and experience. This will help align the résumé more closely with the employer’s expectations and increase the likelihood of passing through automated screening systems.

            For example, if the job listing emphasizes 'Statistical Process Control (SPC),' ensure that Christopher’s experience with similar methodologies is clearly highlighted and described in similar terms.

            Guidance:
            Leverage the provided resources to make the résumé as compelling as possible for the job listing. Focus on enhancing the relevance of the résumé content by aligning it with the job description and emphasizing \(applicant.name)’s qualifications. \(attentionGrabLanguage)

            Prioritize the most relevant background information from the documents provided, particularly those that align directly with the job listing requirements. Use this information to inform your customizations, ensuring that the final résumé is targeted, effective, and stands out.

            You may only modify the résumé values in the following array:
            \(updatableFieldsString)
            The editable résumé value are listed in an array of EditableNodes. An EditableNode includes (1) the résumé value (which your customizations will change) (2) an id, which will be used to update the values in the resume source programatically and (3) a text tree path which is provided to aid in understanding the values in the context of the resume) 

            You will provide your suggested résumé revsions as an array of RevisionNode that will be used call  proposeRevisions(revs: [RevisionNodes]), which is a function that you have access to.

            Background Resources:
            Below are additional resources that may provide context and supporting information for your task:
            \(backgroundDocs)

            Reminder:
            As you finalize the customized résumé, ensure that:
            - **No experience is fabricated.**
            - Skills and experiences are framed in a way that is relevant, compelling, and truthful.
            - The writing is memorable and attention-grabbing to increase the likelihood of catching a recruiter’s eye and prompting a follow-up.
            - The language and skills from the job listing are mirrored where appropriate and consistent with \(applicant.name)’s actual experience.
            - The final résumé is compelling, accurate, and aligned with the job listing’s requirements.
            """

        // Print or return the final prompt
        return prompt

    }
}
