//
//  ResumeQuery.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

import Foundation

@Observable class ResumeApiQuery {
    // MARK: - Properties

    /// Set this to `true` if you want to save a debug file containing the prompt text.
    var saveDebugPrompt: Bool = false

    // JSON Schema for revisions (used to be JSONSchemaResponseFormat from SwiftOpenAI)
    static let revNodeArraySchemaString = """
    {
        "type": "object",
        "properties": {
            "revArray": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "id": {
                            "type": "string",
                            "description": "The identifier for the node provided in the original EditableNode"
                        },
                        "oldValue": {
                            "type": "string",
                            "description": "The original value before revision provided in the original EditableNode"
                        },
                        "newValue": {
                            "type": "string",
                            "description": "The proposed new value after revision"
                        },
                        "valueChanged": {
                            "type": "boolean",
                            "description": "Indicates if the value is changed by the proposed revision."
                        },
                        "why": {
                            "type": "string",
                            "description": "Explanation for the proposed revision. Leave blank if the reason is trivial or obvious."
                        },
                        "isTitleNode": {
                            "type": "boolean",
                            "description": "Indicates whether the node shall be rendered as a title node. This value should not be modified from the value provided in the original EditableNode"
                        }
                    },
                    "required": ["id", "oldValue", "newValue", "valueChanged", "why", "isTitleNode"],
                    "additionalProperties": false
                }
            }
        },
        "required": ["revArray"],
        "additionalProperties": false
    }
    """

    /// System prompt using the abstraction layer message format
    let genericSystemMessage = ChatMessage(
        role: .system,
        content: """
        You are an expert career coach with a specialization in crafting and refining technical resumes to optimize them for job applications. With extensive experience in helping candidates secure interviews at top companies, you understand the importance of aligning resume content with job descriptions and the subtleties of tailoring resumes to specific roles. Your goal is to propose revisions that truthfully showcase the candidate's relevant achievements, experiences, and skills. Make the resume compelling, concise, and closely aligned with the target job posting, without adding any fabricated details.
        """
    )

    // Make this var instead of let so it can be updated
    var applicant: Applicant
    var queryString: String = ""
    let attentionGrab: Int = 2
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
        return res.model!.renderedResumeText
    }

    var resumeJson: String {
        return res.model!.json
    }

    var jobListing: String {
        return res.jobApp?.jobListingString ?? ""
    }

    var updatableFieldsString: String {
        guard let rootNode = res.rootNode else {
            return ""
        }
        let exportDict = TreeNode.traverseAndExportNodes(node: rootNode)
        do {
            let updatableJsonData = try JSONSerialization.data(
                withJSONObject: exportDict, options: .prettyPrinted
            )
            return String(data: updatableJsonData, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    // MARK: - Initialization

    @MainActor
    init(resume: Resume, saveDebugPrompt: Bool = true) {
        // Optionally let users pass in the debug flag during initialization
        res = resume
        applicant = Applicant() // Uses the custom applicant profile
        self.saveDebugPrompt = saveDebugPrompt

        // Debug: print JSON block that will be supplied to the LLM so we can verify content
        print("▶️ updatableFieldsString JSON sent to LLM:\n", updatableFieldsString)
    }

    // Secondary initializer that creates a non-MainActor placeholder applicant
    init(resume: Resume, applicantProfile: ApplicantProfile, saveDebugPrompt: Bool = false) {
        res = resume
        // Create a basic applicant without using the MainActor-isolated initializer
        // This is safe because we're just creating a data container with the provided values
        applicant = Applicant(
            name: applicantProfile.name,
            address: applicantProfile.address,
            city: applicantProfile.city,
            state: applicantProfile.state,
            zip: applicantProfile.zip,
            websites: applicantProfile.websites,
            email: applicantProfile.email,
            phone: applicantProfile.phone
        )
        self.saveDebugPrompt = saveDebugPrompt
    }

    // Method to update the applicant data later
    func updateApplicant(_ newApplicant: Applicant) {
        applicant = newApplicant
    }

    // MARK: - Prompt Building

    func revisionPrompt(_ fb: [FeedbackNode]) -> String {
        let json = fbToJson(fb)
        let prompt = """
        \(applicant.name) has reviewed your proposed revision and has provided feedback. Please revise and rewrite as specified for each FeedbackNode below. Provide your updated revisions as an array of RevNodes (schema attached). The RevNodeArray should only include RevNodes for which your action is required (newValue != oldValue). No response is required for any FeedbackNode for which no action is needed.

        Feedback Nodes:
        \(json ?? "none provided")
        """
        return prompt
    }

    var wholeResumeQueryString: String {
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
