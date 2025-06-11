//
//  ResumeQuery.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

@Observable class ResumeApiQuery {
    // MARK: - Properties

    /// Set this to `true` if you want to save a debug file containing the prompt text.
    var saveDebugPrompt: Bool = false
    
    /// The mode for this query (normal or with clarifying questions)
    var queryMode: ResumeQueryMode = .normal

    // Native SwiftOpenAI JSON Schema for revisions
    static let revNodeArraySchema: JSONSchema = {
        // Define the revision node schema
        let revisionNodeSchema = JSONSchema(
            type: .object,
            properties: [
                "id": JSONSchema(
                    type: .string,
                    description: "The identifier for the node provided in the original EditableNode"
                ),
                "oldValue": JSONSchema(
                    type: .string,
                    description: "The original value before revision provided in the original EditableNode"
                ),
                "newValue": JSONSchema(
                    type: .string,
                    description: "The proposed new value after revision"
                ),
                "valueChanged": JSONSchema(
                    type: .boolean,
                    description: "Indicates if the value is changed by the proposed revision"
                ),
                "why": JSONSchema(
                    type: .string,
                    description: "Explanation for the proposed revision. Leave blank if the reason is trivial or obvious"
                ),
                "isTitleNode": JSONSchema(
                    type: .boolean,
                    description: "Indicates whether the node shall be rendered as a title node. This value should not be modified from the value provided in the original EditableNode"
                ),
                "treePath": JSONSchema(
                    type: .string,
                    description: "The hierarchical path to the node (e.g., 'Resume > Experience > Bullet 1'). Return exactly the same value you received; do NOT modify it"
                )
            ],
            required: ["id", "oldValue", "newValue", "valueChanged", "why", "isTitleNode", "treePath"],
            additionalProperties: false
        )
        
        // Define the RevArray schema
        let revArraySchema = JSONSchema(
            type: .array,
            description: "IMPORTANT: Use exactly 'RevArray' as the property name (capital R)",
            items: revisionNodeSchema
        )
        
        // Define the root schema
        return JSONSchema(
            type: .object,
            properties: [
                "RevArray": revArraySchema
            ],
            required: ["RevArray"],
            additionalProperties: false
        )
    }()
    
    // Native SwiftOpenAI JSON Schema for clarifying questions
    static let clarifyingQuestionsSchema: JSONSchema = {
        // Define the clarifying question schema
        let questionSchema = JSONSchema(
            type: .object,
            properties: [
                "id": JSONSchema(
                    type: .string,
                    description: "A unique identifier for the question (e.g., 'q1', 'q2', 'q3')"
                ),
                "question": JSONSchema(
                    type: .string,
                    description: "The clarifying question to ask the user"
                ),
                "context": JSONSchema(
                    type: .string,
                    description: "Context explaining why this question is being asked and how it will help improve the resume"
                )
            ],
            required: ["id", "question", "context"],
            additionalProperties: false
        )
        
        // Define the questions array
        let questionsArraySchema = JSONSchema(
            type: .array,
            description: "Array of clarifying questions to ask the user (maximum 3 questions)",
            items: questionSchema
        )
        
        // Define the root schema
        return JSONSchema(
            type: .object,
            properties: [
                "questions": questionsArraySchema,
                "proceedWithRevisions": JSONSchema(
                    type: .boolean,
                    description: "Set to true if you have sufficient information to proceed with revisions without asking questions, false if you need to ask clarifying questions"
                )
            ],
            required: ["questions", "proceedWithRevisions"],
            additionalProperties: false
        )
    }()

    /// System prompt using the native SwiftOpenAI message format
    let genericSystemMessage = LLMMessage.text(
        role: .system,
        content: """
        You are an expert career coach with a specialization in crafting and refining technical resumes to optimize them for job applications. With extensive experience in helping candidates secure interviews at top companies, you understand the importance of aligning resume content with job descriptions and the subtleties of tailoring resumes to specific roles. Your goal is to propose revisions that truthfully showcase the candidate's relevant achievements, experiences, and skills. Make the resume compelling, concise, and closely aligned with the target job posting, without adding any fabricated details.
        """
    )

    // Make this var instead of let so it can be updated
    var applicant: Applicant
    var queryString: String = ""
    let res: Resume

    // MARK: - Derived Properties

    var backgroundDocs: String {
        let bgrefs = res.enabledSources
        if bgrefs.isEmpty {
            return ""
        } else {
            return bgrefs.map { $0.name + ":\n" + $0.content + "\n\n" }.joined()
        }
    }

    var resumeText: String {
        if res.textRes == "" {
            Logger.debug("⚠️BLANK TEXT RES⚠️")
            return res.model!.renderedResumeText
        } else { return res.textRes }
    }

    var resumeJson: String {
        return res.model!.json
    }

    var jobListing: String {
        return res.jobApp?.jobListingString ?? ""
    }

    var updatableFieldsString: String {
        guard let rootNode = res.rootNode else {
            Logger.debug("⚠️ updatableFieldsString: rootNode is nil!")
            return ""
        }
        let exportDict = TreeNode.traverseAndExportNodes(node: rootNode)
        do {
            let updatableJsonData = try JSONSerialization.data(
                withJSONObject: exportDict, options: .prettyPrinted
            )
            let returnString = String(data: updatableJsonData, encoding: .utf8) ?? ""
            Logger.verbose("🫥🫥🫥🫥🫥🫥 UPDATABLE NODES 🫥🫥🫥🫥🫥🫥")
            Logger.verbose(returnString)
            return returnString
        } catch {
            return ""
        }
    }

    var allEditableFieldsString: String {
        guard let rootNode = res.rootNode else {
            return ""
        }
        let exportDict = TreeNode.traverseAndExportAllEditableNodes(node: rootNode)
        do {
            let updatableJsonData = try JSONSerialization.data(
                withJSONObject: exportDict, options: .prettyPrinted
            )
            let returnString = String(data: updatableJsonData, encoding: .utf8) ?? ""
            Logger.verbose("🫥🫥🫥🫥🫥🫥 ALL EDITABLE NODES 🫥🫥🫥🫥🫥🫥")
            Logger.verbose(returnString)
            return returnString
        } catch {
            return ""
        }
    }

    // MARK: - Initialization

    init(resume: Resume, saveDebugPrompt: Bool = true) {
        // Optionally let users pass in the debug flag during initialization
        res = resume
        
        // Create a complete applicant profile with default values to avoid @MainActor issues
        let profile = ApplicantProfile() // Uses default values from ApplicantProfile init
        applicant = Applicant(
            name: profile.name,
            address: profile.address,
            city: profile.city,
            state: profile.state,
            zip: profile.zip,
            websites: profile.websites,
            email: profile.email,
            phone: profile.phone
        )
        self.saveDebugPrompt = saveDebugPrompt
    }



    // Method to update the applicant data later
    func updateApplicant(_ newApplicant: Applicant) {
        applicant = newApplicant
    }

    // MARK: - Prompt Building

    @MainActor
    func revisionPrompt(_ fb: [FeedbackNode]) async -> String {
        // Resume text should already be up-to-date from the rendering called in aiResubmit
        // but we'll ensure it again as a safety measure
        try? await res.ensureFreshRenderedText()

        // At this point, fb should already contain only nodes that need revision
        // due to our filtering in ReviewView's nextNode method
        let json = fbToJson(fb)

        // Extract node IDs for more explicit instructions
        let nodeIDs = fb.map { "\($0.id)" }.joined(separator: ", ")

        let prompt = """
        \(applicant.name) has reviewed your proposed revision and has provided feedback. Please revise and rewrite ONLY the specific nodes listed below. Provide your updated revisions as an array of RevNodes (schema attached).

        IMPORTANT CONSTRAINTS - READ CAREFULLY:
        • ONLY return nodes for the specific IDs provided in the feedback list below: [\(nodeIDs)]
        • Do NOT include any nodes that aren't in the feedback list, even if you worked on them previously
        • Do NOT include nodes that have already been accepted or don't need changes
        • The resume text below INCLUDES all previously accepted changes
        • Do NOT change the "id" or "treePath" fields — return them exactly as received

        The ONLY nodes you should provide revisions for are in this feedback list:
        \(json ?? "none provided")

        Here is the CURRENT VERSION of the resume with all accepted changes applied:
        \(resumeText)

        Remember: Your response should ONLY include nodes for the IDs listed above. Do not include any other nodes.
        """
        return prompt
    }

    @MainActor
    func wholeResumeQueryString() async -> String {
        // Ensure the resume's rendered text is up-to-date by awaiting the export/render process.
        // This assumes res.ensureFreshRenderedText() will update res.model.renderedResumeText.
        try? await res.ensureFreshRenderedText()
        

        // Generate language that controls how strongly we emphasize achievements
//        switch res.attentionGrab {
//        case 0:
//            attentionGrabLanguage = ""
//        case 1:
//            attentionGrabLanguage =
//                "Highlight key skills and experiences, but maintain a balanced, professional tone."
//        case 2:
//            attentionGrabLanguage =
//                "Make the resume stand out by emphasizing relevant skills and achievements. Maintain clear, concise language."
//        case 3:
//            attentionGrabLanguage =
//                "Strongly emphasize achievements and distinct accomplishments to make a memorable impression."
//        case 4:
//            attentionGrabLanguage =
//                "Push for very memorable, eye-catching statements. Risk-taking is acceptable to stand out, but the content must remain truthful."
//        default:
//            attentionGrabLanguage = ""
//        }

        // Build the improved prompt
        let prompt = """
        ================================================================================
        LATEST RÉSUMÉ (PLAIN TEXT):
        \(resumeText)
        ================================================================================
        This is the most recent version of \(applicant.name)'s résumé in plain text, generated from the following JSON data using a templating system. This system also builds HTML and PDF outputs from the same JSON.

        RÉSUMÉ SOURCE JSON:
        \(resumeJson)
        ================================================================================
        ================================================================================
        GOAL:
        Our objective is to secure \(applicant.name) an interview for the following position:

        JOB LISTING:
        \(jobListing)

        TASK:
        - Review \(applicant.name)’s latest résumé and background documents.
        - Propose revisions that align with the listed job requirements, reflect the key responsibilities and skills mentioned, and truthfully enhance the resume’s impact.
        - Incorporate relevant keywords from the job listing to help pass automated screeners.
        - Ensure you do not introduce any fabricated experience.
        - Provide all revisions as structured data in an array of RevNodes (RevArray) matching the schema below.

        IMPORTANT:
        1. Only modify the fields in the EditableNodes array below.
        2. For each field that needs no change, set newValue to "" and valueChanged to false.
        3. For each field that requires a change, propose newValue, set valueChanged to true, and include a “why” explanation if non-trivial.
        4. The final resume must remain truthful, but should strongly emphasize relevant achievements and mirror the language of the job listing where appropriate.
        5. Avoid redundant phrasing among bullet points; keep language varied if multiple items share similar responsibilities or skills.
        6. Safeguard the broader skill set if it is relevant to roles beyond the target position, but do prioritize clarity and relevance to this specific job.
        7. Keep formatting cues consistent with the style implied by the existing resume content.

        ================================================================================
        EDITABLE NODES:
        \(updatableFieldsString)
        ================================================================================
        BACKGROUND DOCUMENTS:
        \(backgroundDocs)
        ================================================================================
        OUTPUT INSTRUCTIONS:
        - Return your proposed revisions as JSON matching the RevNode array schema provided.
        - For each original EditableNode, include exactly one RevNode in the RevArray. The array indices should match the order of EditableNodes in the updatableFieldsString.
        - If no change is required for a given node, set “newValue” to "" and “valueChanged” to false.
        - The “why” field can be an empty string if the reason is self-explanatory.
        - Do **not** modify the "id" or "treePath" fields. Always return the exact same values you received for those fields for each node.

        SUMMARY:
        Make the resume as compelling and accurate as possible for the target job. Keep it honest, relevant, and ensure that any additions or modifications support \(applicant.name)’s candidacy for the role. Use strategic language to highlight achievements, mirror core keywords from the job posting, and present a polished, stand-out resume.
        ================================================================================
        """

        // If debug flag is set, save the prompt to a text file in the user's Downloads folder.
        if saveDebugPrompt {
            savePromptToDownloads(content: prompt, fileName: "promptDebug.txt")
        }

        return prompt
    }

    /// Generate prompt for clarifying questions workflow
    /// Returns the full resume context with clarifying questions instructions
    @MainActor
    func clarifyingQuestionsPrompt() async -> String {
        // Get the full resume context
        let fullResumeContext = await wholeResumeQueryString()
        
        // Add clarifying questions instruction
        let clarifyingQuestionsInstruction = """
        
        ================================================================================
        CLARIFYING QUESTIONS MODE
        ================================================================================
        
        Before proposing revisions, you have two options:
        
        1. **Ask Clarifying Questions** (up to 3): If you need more information to provide better, more targeted revisions
        2. **Proceed Directly**: If you have sufficient information to proceed with revisions
        
        Consider asking about:
        - Specific skills or experiences to emphasize for this role
        - Achievements that could be quantified or better highlighted  
        - Technologies, methodologies, or certifications to prioritize
        - Industry-specific terminology or focus areas
        - Career trajectory or role-specific accomplishments
        
        If you choose to ask questions, they should be:
        - Specific and actionable
        - Focused on improving relevance to this particular job
        - Designed to gather information not already clear from the resume and job listing
        
        Respond with either clarifying questions OR set proceedWithRevisions to true.
        ================================================================================
        """
        
        return fullResumeContext + clarifyingQuestionsInstruction
    }

    // MARK: - Debugging Helper

    /// Saves the provided prompt text to the user's `Downloads` folder for debugging purposes.
    private func savePromptToDownloads(content: String, fileName: String) {
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
        let fileURL = downloadsURL.appendingPathComponent(fileName)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {}
    }
}
