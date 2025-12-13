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
                This is a bootstrap tool used only during conversation initialization. \
                After receiving developer instructions for a new phase, call this tool to acknowledge receipt and signal readiness. \
                Proceeed to steps in interview when tool response is received.
                RETURNS: { "status": "completed", "content": "I am ready to begin. + {{instructions}}" }
                USAGE: Call this immediately after receiving phase instructions, before attempting any other actions.
                """,
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }()
    init() {}
    var name: String { OnboardingToolName.agentReady.rawValue }
    var description: String {
        "Signal that you are ready to begin after receiving phase instructions. Returns {status: completed, content: I am ready to begin {{instructions}}}."
    }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        var result = JSON()
        result["status"].string = "completed"
        result["content"].string = """
Ready. Follow this workflow ONE STEP AT A TIME:

## Step 1: Profile Intake
Write welcome preamble: "Welcome! I'm here to help you build a comprehensive, evidence-backed profile of your career. This isn't a test—it's a collaborative session to uncover the great work you've done. We'll use this profile to create perfectly tailored resumes and cover letters later. Let me open your profile card."
Then call `get_applicant_profile`. STOP and wait for user completion.

## Step 2: Process Profile Data
Check the `get_applicant_profile` tool response:
- If `profile_data` is included: Profile is pre-validated. Skip to Step 3 immediately.
- If UPLOAD path: Parse ArtifactRecord → call `validate_applicant_profile` → wait for validation, then call `validated_applicant_profile_data()`.
- If FORM path without profile_data: Call `validated_applicant_profile_data()` to retrieve.

## Step 3: Photo (Optional)
Check `basics.image` in profile data (from tool response or validated_applicant_profile_data):
- If present: Skip to Step 4
- If empty: Ask "Would you like to add a headshot?" Then STOP and wait.
  - If yes: Call `get_user_upload` with title="Upload Headshot", target_key="basics.image", allowed_types=["jpg","jpeg","png"]
  - If no: Continue to Step 4

## Step 4: Resume Upload Offer
Call `list_artifacts` to check for existing resume. A .vcf does NOT count.
- If resume exists: Skip to timeline workflow
- If no resume: In a SINGLE response, write a brief preamble ("I'll open the resume upload form") AND IMMEDIATELY call `get_user_upload` with title="Upload Resume/CV", target_phase_objectives=["skeleton_timeline"]. Do NOT wait between preamble and tool call—they must be in the same message.

## Step 5: Timeline Editor
After resume step completes:
1. Call `display_timeline_entries_for_review` to activate editor
2. For each position, call `create_timeline_card` with: title, organization, location, start, end
3. User can edit cards directly; trust their changes without confirming each one
4. When user requests changes via chat: use get_timeline_entries, then delete/create/update cards programmatically
5. When complete, call `submit_for_validation(validation_type="skeleton_timeline")`

## Step 6: Enabled Sections
REQUIRED FORMAT - the proposed_sections object is MANDATORY:
```json
{"proposed_sections": {"work": true, "education": true, "skills": true, "projects": true, "publications": false, "awards": false}, "rationale": "optional"}
```
Do NOT call with only rationale - that will fail. The proposed_sections object with section keys mapped to boolean values is required.
Propose sections based on what user mentioned (publications: true if they have papers, awards: false if none mentioned).
Wait for user confirmation.

## Step 7: Dossier Seed → Phase 2
Ask 2-3 quick questions about goals/target roles. For each answer, call persist_data(dataType="candidate_dossier_entry").
Then IMMEDIATELY call `next_phase` to transition to Phase 2. Don't wait for user to request it.

## Rules
- One step per message cycle (preamble + tool call = one step, not two)
- Always write preamble text BEFORE tool calls in the SAME message
- When a step says to call a tool, include both preamble AND tool call in your response—don't wait
- Wait for user response only when explicitly told to STOP and wait
- Trust user edits to timeline cards
"""
        result["disable_after_use"].bool = true
        return .immediate(result)
    }
}
