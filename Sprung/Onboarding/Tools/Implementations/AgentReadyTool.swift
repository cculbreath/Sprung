import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Bootstrap tool used during conversation initialization.
/// The LLM calls this after receiving phase instructions to signal readiness,
/// triggering the system to send "I am ready to begin" and start the interview.
struct AgentReadyTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Signal that you have received and understood the phase instructions and are ready to begin the interview.

                This is a bootstrap tool used only during conversation initialization. After receiving developer instructions for a new phase, call this tool to acknowledge receipt and signal readiness. Proceeed to steps in interview when tool response is received.

                RETURNS: { "status": "completed", "content": "I am ready to begin. + {{instructions}}" }

                USAGE: Call this immediately after receiving phase instructions, before attempting any other actions.
                """,
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }()

    init() {}

    var name: String { "agent_ready" }
    var description: String { "Signal that you are ready to begin after receiving phase instructions. Returns {status: completed, content: I am ready to begin {{instructions}}}." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Return simple acknowledgment
        // The "I am ready to begin" message will be sent AFTER the tool response
        // is delivered to the LLM (handled in ToolExecutionCoordinator)
        var result = JSON()
        result["status"].string = "completed"
        result["content"].string = """
I am ready to begin. Follow this EXACT sequence ONE STEP AT A TIME:

STEP 1: In a SINGLE response, do BOTH of these:
   a) Send this welcome message to the user:
      "Welcome. I'm here to help you build a comprehensive, evidence-backed profile of your career. This isn't a test; it's a collaborative session to uncover the great work you've done. We'll use this profile to create perfectly tailored resumes and cover letters later."
   b) Call `get_applicant_profile` tool to present the profile intake card.

   Then STOP. Do not proceed further in this message.

STEP 2: WAIT for user to complete profile intake. When completed, you will receive a user message indicating completion.

STEP 3: Process the profile data based on how user provided it:
   - If user UPLOADED a document: Parse the provided ArtifactRecord to extract contact info, then call `validate_applicant_profile` for user confirmation.
   - If user entered data via FORM (contacts import or manual entry): The data arrives already validated. DO NOT call `validate_applicant_profile`. Acknowledge receipt and proceed to STEP 4.

STEP 4: After profile is validated and persisted (you'll receive confirmation), call `validated_applicant_profile_data()` to retrieve the persisted profile.

STEP 5: Check the retrieved profile's `basics.image` field:
   - If image is present: Acknowledge existing photo, then immediately proceed to STEP 6 (skeleton_timeline) in the SAME message.
   - If image is empty: Ask user ONLY this question: "Would you like to add a headshot photograph to your résumé profile?"

   CRITICAL: After asking about photo, STOP your message. DO NOT ask about skeleton_timeline yet.

   WAIT for user response to photo question:
     - If user says yes: Call `get_user_upload` with these EXACT parameters:
       - title: "Upload Headshot"
       - prompt_to_user: "Please provide a professional quality photograph for inclusion on résumé layouts that require a picture"
       - target_key: "basics.image" (REQUIRED - saves photo to profile)
       - target_deliverable: "ApplicantProfile"
       - target_phase_objectives: ["skeleton_timeline"]
       - allowed_types: ["jpg", "jpeg", "png"]
       Then WAIT for upload completion. After upload completes, proceed to STEP 6.
     - If user says no: Proceed to STEP 6.

STEP 6: Begin skeleton_timeline workflow.

   First, check if a resume/CV was already uploaded during the applicant_profile workflow (STEP 3):
   - If YES (artifact exists): Use that document to extract timeline data and proceed directly to timeline card workflow below.
   - If NO (no resume artifact): Continue to resume upload step.

   If no resume exists yet:
   - Send chat message: "I've opened an upload form for your resume or CV. If you prefer to skip the upload and build your timeline conversationally instead, you can cancel the form and we'll do it through chat."
   - Immediately call `get_user_upload` with:
     - title: "Upload Resume/CV"
     - prompt_to_user: "Please upload your resume or CV for timeline extraction"
     - target_phase_objectives: ["skeleton_timeline"]
   - WAIT for user action:
     - If they UPLOAD: Extract timeline data and proceed to timeline card workflow
     - If they SKIP/CANCEL: Begin conversational interview about work history (most recent first)

   Timeline card workflow (applies to BOTH document extraction AND conversational paths):
   - Call `display_timeline_entries_for_review` first to activate timeline EDITOR in Tool Pane
   - For EACH position, call `create_timeline_card` with: title, organization, location, start, end
   - One card per previous position/role
   - Cards appear in the editor immediately when created
   - User can edit, delete, reorder cards and click "Save Timeline" to send changes back to you

   CRITICAL - TRUST USER EDITS:
   - When user clicks "Save Timeline" after making changes, ALL edits are PURPOSEFUL and INTENTIONAL
   - ASSUME deleted cards were meant to be deleted - don't question or ask to restore them
   - ASSUME modified fields (dates, titles, locations) are corrections - don't second-guess them
   - ASSUME reordered cards reflect user's preferred chronology
   - ONLY ask about changes if there's a genuine conflict (e.g., overlapping dates that don't make sense)
   - DO NOT confirm every single edit - trust the user knows what they want
   - Simply acknowledge "I've updated the timeline with your changes" and move forward

   - Continue refining cards based on user feedback until timeline is complete
   - When timeline is complete, call `submit_for_validation` with validation_type="skeleton_timeline" to present FINAL APPROVAL UI
   - User clicks "Confirm" to finalize timeline
   - After confirmation, mark skeleton_timeline objective complete

RULES:
- Process ONE STEP per message cycle
- NEVER combine the photo question with skeleton_timeline questions
- WAIT for user response before proceeding to next step
- DO NOT ask for contact details via chat - use the profile intake card UI
"""
        result["disable_after_use"].bool = true
        return .immediate(result)
    }
}
