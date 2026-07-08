//
//  PromptLibrary.swift
//  Sprung
//
//  Centralized loading of LLM prompts from resource files.
//  Prompts are stored as .txt or .md files in Resources/Prompts/ for easier editing and version control.
//

import AppKit
import Foundation

/// Thrown when a required prompt resource cannot be found in the app bundle.
enum PromptLibraryError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        "App resources appear corrupted — please reinstall."
    }
}

/// Centralized library for loading LLM prompts from resource files.
/// All prompts are stored in Sprung/Onboarding/Resources/Prompts/ directory.
///
/// A missing bundled prompt is a packaging-level corruption (the resources ship
/// inside the app). `loadPrompt(named:)` throws on that condition so the failure
/// is never silently swallowed; the cached accessors below route through
/// `prompt(named:)`, which surfaces a single user-facing "reinstall" alert instead
/// of poisoning the LLM with a placeholder string.
enum PromptLibrary {

    // MARK: - Interview System Prompt

    /// Base system prompt for the onboarding interview agent
    static let interviewBaseSystem: String = { prompt(named: "interview_base_system") }()

    // MARK: - Interview Phase Prompts

    /// Phase 1 introductory prompt (Voice & Context)
    static let phase1Intro: String = { prompt(named: "phase1_intro_prompt") }()

    /// Phase 2 introductory prompt (Career Story)
    static let phase2Intro: String = { prompt(named: "phase2_intro_prompt") }()

    /// Phase 3 introductory prompt (Evidence Collection)
    static let phase3Intro: String = { prompt(named: "phase3_intro_prompt") }()

    /// Phase 4 introductory prompt (Strategic Synthesis)
    static let phase4Intro: String = { prompt(named: "phase4_intro_prompt") }()

    // MARK: - Document Extraction Prompts

    /// Document summarization prompt template.
    /// Contains placeholder: {FILENAME}
    /// The document content arrives as a preceding content block.
    static let documentSummaryTemplate: String = { prompt(named: "document_summary_prompt") }()

    // MARK: - Git Agent Prompts

    /// System prompt for git repository analysis agent
    static let gitAgentSystemPrompt: String = { prompt(named: "git_agent_system_prompt") }()

    /// Author filter template for git agent
    /// Contains placeholder: {AUTHOR}
    static let gitAgentAuthorFilter: String = { prompt(named: "git_agent_author_filter") }()

    // MARK: - Tool Workflow Prompts

    /// Agent ready tool workflow summary
    static let agentReadyWorkflow: String = { prompt(named: "agent_ready_workflow") }()

    // MARK: - Skill Bank + Narrative KC Prompts

    /// Skill bank extraction prompt template
    /// Contains placeholders: {DOC_ID}, {FILENAME}, {LOCATION_GUIDANCE}
    /// The document content arrives as a preceding content block.
    static let skillBankExtractionTemplate: String = { prompt(named: "skill_bank_extraction") }()

    /// Narrative knowledge card extraction prompt template
    /// Contains placeholders: {DOC_ID}, {FILENAME}, {LOCATION_GUIDANCE}
    /// The document content arrives as a preceding content block.
    static let kcExtractionTemplate: String = { prompt(named: "kc_extraction") }()

    // MARK: - Inference Guidance Prompts

    /// Voice profile extraction prompt template
    /// Contains placeholder: {WRITING_SAMPLES}
    static let voiceProfileTemplate: String = { prompt(named: "voice_profile_extraction") }()

    // MARK: - Prompt Loading

    /// Loads a prompt from a resource file in the Prompts directory.
    /// - Parameter name: The filename without extension (supports .txt and .md)
    /// - Returns: The prompt content as a string
    /// - Throws: `PromptLibraryError.missingResource` when the file is absent from the bundle
    static func loadPrompt(named name: String) throws -> String {
        for ext in ["txt", "md"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Prompts"),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        Logger.error("⚠️ Failed to load prompt: \(name)")
        throw PromptLibraryError.missingResource(name)
    }

    /// Non-throwing accessor used by the cached prompt properties. On a missing
    /// resource it surfaces a single "reinstall" alert (instead of returning a
    /// placeholder that would silently poison the LLM) and yields an empty string
    /// so the caller fails loudly-via-alert rather than crashing.
    private static func prompt(named name: String) -> String {
        do {
            return try loadPrompt(named: name)
        } catch {
            surfaceCorruptedResourcesAlert()
            return ""
        }
    }

    @MainActor private static var corruptionAlertShown = false

    private static func surfaceCorruptedResourcesAlert() {
        Task { @MainActor in
            guard !corruptionAlertShown else { return }
            corruptionAlertShown = true
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "App Resources Missing"
            alert.informativeText = """
            Some of Sprung's built-in resources couldn't be loaded, so the onboarding interview can't run correctly. Please reinstall the app.
            """
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - Template Substitution Helpers

    /// Replaces placeholders in a template string
    /// - Parameters:
    ///   - template: Template string with {PLACEHOLDER} markers
    ///   - replacements: Dictionary of placeholder names to values
    /// - Returns: String with placeholders replaced
    static func substitute(template: String, replacements: [String: String]) -> String {
        var result = template
        for (key, value) in replacements {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}
