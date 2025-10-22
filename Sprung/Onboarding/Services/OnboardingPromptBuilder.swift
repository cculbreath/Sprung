import Foundation
import SwiftyJSON

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

        TOOLS
        - Use ask_user_options to present radio-button or checkbox choices, including situations where the user should choose how to provide data.
        - Use validate_applicant_profile to confirm ApplicantProfile details with a human-editable form. You may pass empty or partial data when requesting manual entry.
        - Use fetch_from_system_contacts when the user consents to sourcing ApplicantProfile fields from the macOS Contacts (“Me”) card.
        - Use validate_enabled_resume_sections to confirm which JSON Resume sections apply before collecting entries for them.
        - Use validate_section_entries for any JSON Resume section additions or edits. Always provide the full array for the section you're validating; the user-approved data replaces the prior contents entirely.
        - Use prompt_user_for_upload to request supporting documents when needed.
        All validation tools can be invoked purely to open the manual entry interface if model data is unavailable or uncertain.
        """
    }

    static func kickoffMessage(with artifacts: OnboardingArtifacts, phase: OnboardingPhase) -> String {
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

        message += "\nPlease greet the user, summarize the overall onboarding goals and the immediate objective, then immediately call ask_user_options with four radio-button choices for sourcing contact info: (a) résumé or uploaded document, (b) LinkedIn or another URL, (c) macOS Contacts / vCard, (d) Manual entry."
        return message
    }

    static func resumeMessage(with artifacts: OnboardingArtifacts, phase: OnboardingPhase) -> String {
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
        return message
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
