import Foundation
import SwiftyJSON

struct OnboardingPromptSpec {
    let message: String
    let preferredModelId: String?
    let reasoning: OpenRouterReasoning?

    init(
        message: String,
        preferredModelId: String? = nil,
        reasoning: OpenRouterReasoning? = nil
    ) {
        self.message = message
        self.preferredModelId = preferredModelId
        self.reasoning = reasoning
    }
}

enum OnboardingPromptBuilder {
    static func systemPrompt() -> String {
        """
        You are Sprung's dedicated onboarding interviewer. Maintain a collaborative tone, focus on clarifying the candidate's work history, strengths, and preferences, and explicitly track uncertainties. Follow the structured JSON output schema:
        {
          "assistant_reply": String,
          "next_questions": [ { "id": String, "question": String, "target": String? } ]?,
          "delta_update": [Object]? | Object?,
          "knowledge_cards": [Object]?,
          "fact_ledger": [Object]?,
          "skill_map_delta": Object?,
          "style_profile": Object?,
          "writing_samples": [Object]?,
          "profile_context": String?,
          "needs_verification": [String]?,
          "tool_calls": [ { "id": String, "tool": String, "args": Object } ]?
        }
        Use null instead of omitting when a field applies but no data is available. Never emit multiple JSON blocks.

        STYLE
        - Be concise and conversational (≤4 follow-ups per topic).
        - Coach the user toward quantified, verifiable statements.
        - Surface opportunities to upload artifacts or writing samples at each phase.
        - Summarize progress regularly and highlight remaining uncertainties.

        SCHEMA
        - Include every tool argument specified in the schema. Use an empty string (\"\"), empty array ([]), or empty object ({}) when the real value is unknown.
        - ApplicantProfile strings must always be present; return \"\" for any contact field you cannot populate yet and [] for empty collections.
        - Provide default selections such as \"selection_style\": \"single\" and explicit booleans for flags like \"multiple\" or \"allow_cancel\".

        TOOLS AND WAITING PATTERN
        When you call a tool that requires user input (ask_user_options, validate_applicant_profile, validate_section_entries, prompt_user_for_upload, etc.), it will immediately return {\"status\": \"waiting_for_user\"}.

        CRITICAL: When you receive {\"status\": \"waiting_for_user\"}:
        1. Respond with a brief message acknowledging the form/prompt you've shown (e.g., \"Please make your selection in the form to the left. We'll continue once you've chosen an option.\")
        2. DO NOT call any other tools
        3. DO NOT continue with additional reasoning or questions
        4. STOP and wait for the user's response

        The user's selection will be sent back to you in a subsequent message, at which point you can proceed with the next step.

        TOOL USAGE:
        - Use ask_user_options to present radio-button or checkbox choices, including situations where the user should choose how to provide data.
        - Use validate_applicant_profile to confirm ApplicantProfile details with a human-editable form. Always include every field; use \"\" when data is unknown.
        - Use fetch_from_system_contacts when the user consents to sourcing ApplicantProfile fields from the macOS Contacts ("Me") card.
        - Use validate_enabled_resume_sections to confirm which JSON Resume sections apply before collecting entries for them.
        - Use validate_section_entries for any JSON Resume section additions or edits. Always provide the full array for the section you're validating; the user-approved data replaces the prior contents entirely.
        - Use prompt_user_for_upload to request supporting documents when needed.
        All validation tools can be invoked purely to open the manual entry interface if model data is unavailable or uncertain.
        """
    }

    static func kickoffPrompt(with artifacts: OnboardingArtifacts, phase: OnboardingPhase) -> OnboardingPromptSpec {
        var message = "We are beginning an onboarding interview."

        if let profile = artifacts.applicantProfile, let raw = profile.rawString(options: []) {
            message += "\nCurrent applicant_profile JSON: \(raw)"
        }
        if let defaults = artifacts.defaultValues, let raw = defaults.rawString(options: []) {
            message += "\nCurrent default_values JSON: \(raw)"
        }
        if !artifacts.knowledgeCards.isEmpty,
           let raw = JSON(artifacts.knowledgeCards).rawString(options: []) {
            message += "\nExisting knowledge_cards: \(raw)"
        }
        if let skillMap = artifacts.skillMap, let raw = skillMap.rawString(options: []) {
            message += "\nExisting skills_index: \(raw)"
        }
        if !artifacts.factLedger.isEmpty,
           let raw = JSON(artifacts.factLedger).rawString(options: []) {
            message += "\nExisting fact_ledger entries: \(raw)"
        }
        if let styleProfile = artifacts.styleProfile,
           let raw = styleProfile.rawString(options: []) {
            message += "\nExisting style_profile: \(raw)"
        }
        if !artifacts.writingSamples.isEmpty,
           let raw = JSON(artifacts.writingSamples).rawString(options: []) {
            message += "\nKnown writing_samples: \(raw)"
        }
        if let context = artifacts.profileContext {
            message += "\nCurrent profile_context: \(context)"
        }

        let directive = phaseDirective(for: phase)
        if let directiveText = directive.rawString(options: [.sortedKeys]) {
            message += "\nActive phase directive: \(directiveText)"
        }
        message += "\nFocus summary: \(phase.focusSummary)"
        message += "\nExpected outputs: \(phase.expectedOutputs.joined(separator: " | "))"

        message += """

KICKOFF WORKFLOW:
1. Greet the user warmly
2. Explain that you'll be asking questions and collecting documents to build up a store of information to generate accurate and tailored resumes
3. Explain that you'll start with the basics: name, address, contact information, etc.
4. Ask the user: "Do you have a document or resource that I can use for this information?"
5. Immediately call the ask_user_options tool with these four radio-button options:
   - id: "resume_doc", title: "Résumé or uploaded document", description: "Parse fields from your most recent résumé or CV"
   - id: "linkedin", title: "LinkedIn or URL", description: "Parse fields from a LinkedIn profile or other public URL"
   - id: "macos_contacts", title: "macOS Contacts / vCard", description: "Use your macOS Contacts card or vCard export"
   - id: "manual_entry", title: "Manual entry", description: "Enter contact details manually"
6. The tool will return {"status": "waiting_for_user"}
7. When you see this status, respond with: "Please make your selection in the form to the left. We'll continue once you've chosen an option."
8. STOP. Do not call any other tools or continue reasoning. Wait for the user's response.
"""
        return OnboardingPromptSpec(
            message: message,
            preferredModelId: "openai/gpt-5-nano",
            reasoning: nil
        )
    }

    static func resumePrompt(with artifacts: OnboardingArtifacts, phase: OnboardingPhase) -> OnboardingPromptSpec {
        var message = "We are resuming the onboarding interview."

        if let profile = artifacts.applicantProfile, let raw = profile.rawString(options: []) {
            message += "\nCurrent applicant_profile JSON: \(raw)"
        }
        if let defaults = artifacts.defaultValues, let raw = defaults.rawString(options: []) {
            message += "\nCurrent default_values JSON: \(raw)"
        }
        if !artifacts.knowledgeCards.isEmpty,
           let raw = JSON(artifacts.knowledgeCards).rawString(options: []) {
            message += "\nExisting knowledge_cards: \(raw)"
        }
        if let skillMap = artifacts.skillMap, let raw = skillMap.rawString(options: []) {
            message += "\nExisting skills_index: \(raw)"
        }
        if !artifacts.factLedger.isEmpty,
           let raw = JSON(artifacts.factLedger).rawString(options: []) {
            message += "\nExisting fact_ledger entries: \(raw)"
        }
        if let styleProfile = artifacts.styleProfile,
           let raw = styleProfile.rawString(options: []) {
            message += "\nExisting style_profile: \(raw)"
        }
        if !artifacts.writingSamples.isEmpty,
           let raw = JSON(artifacts.writingSamples).rawString(options: []) {
            message += "\nKnown writing_samples: \(raw)"
        }
        if let context = artifacts.profileContext {
            message += "\nCurrent profile_context: \(context)"
        }
        if !artifacts.needsVerification.isEmpty,
           let raw = JSON(artifacts.needsVerification).rawString(options: []) {
            message += "\nOutstanding needs_verification: \(raw)"
        }

        let directive = phaseDirective(for: phase)
        if let directiveText = directive.rawString(options: [.sortedKeys]) {
            message += "\nActive phase directive: \(directiveText)"
        }
        message += "\nFocus summary: \(phase.focusSummary)"

        message += "\nPlease provide a concise recap of confirmed progress, recap open needs_verification items, and continue with the next best questions for this phase."
        return OnboardingPromptSpec(message: message)
    }

    static func phaseDirective(for phase: OnboardingPhase) -> JSON {
        JSON([
            "type": "phase_transition",
            "phase": phase.rawValue,
            "focus": phase.focusSummary,
            "expected_outputs": JSON(phase.expectedOutputs),
            "interview_prompts": JSON(phase.interviewPrompts)
        ])
    }
}
