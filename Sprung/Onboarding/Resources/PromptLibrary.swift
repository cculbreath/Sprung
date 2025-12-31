//
//  PromptLibrary.swift
//  Sprung
//
//  Centralized loading of LLM prompts from resource files.
//  Prompts are stored as .txt or .md files in Resources/Prompts/ for easier editing and version control.
//

import Foundation

/// Centralized library for loading LLM prompts from resource files.
/// All prompts are stored in Sprung/Onboarding/Resources/Prompts/ directory.
enum PromptLibrary {

    // MARK: - Interview Phase Prompts

    /// Phase 1 introductory prompt (Voice & Context)
    static let phase1Intro: String = {
        loadPrompt(named: "phase1_intro_prompt")
    }()

    /// Phase 2 introductory prompt (Career Story)
    static let phase2Intro: String = {
        loadPrompt(named: "phase2_intro_prompt")
    }()

    /// Phase 3 introductory prompt (Evidence Collection)
    static let phase3Intro: String = {
        loadPrompt(named: "phase3_intro_prompt")
    }()

    /// Phase 4 introductory prompt (Strategic Synthesis)
    static let phase4Intro: String = {
        loadPrompt(named: "phase4_intro_prompt")
    }()

    // MARK: - Fact-Based Knowledge Card Prompts

    /// System prompt for fact-based KC extraction
    /// Contains placeholders: {CARD_ID}, {CARD_TYPE}, {TITLE}
    static let kcFactExtractionSystem: String = {
        loadPrompt(named: "kc_fact_extraction_system")
    }()

    /// Initial prompt template for fact-based KC extraction
    /// Contains placeholders: {CARD_ID}, {CARD_TYPE}, {TITLE}, {TIMELINE_ENTRY}, {NOTES},
    /// {CARD_INVENTORY_JSON}, {ASSIGNED_ARTIFACTS}, {OTHER_ARTIFACTS}, {EXTRACTION_CHECKLIST}
    static let kcFactExtractionInitial: String = {
        loadPrompt(named: "kc_fact_extraction_initial")
    }()

    /// System prompt for expanding existing KC with new evidence
    static let kcExpandSystem: String = {
        loadPrompt(named: "kc_expand_system")
    }()

    /// Initial prompt template for KC expansion
    /// Contains placeholders: {CARD_ID}, {CARD_TYPE}, {TITLE}, {ORGANIZATION}, {TIME_PERIOD},
    /// {FACT_COUNT}, {EXISTING_FACTS_JSON}, {EXISTING_BULLETS_JSON}, {EXISTING_TECHNOLOGIES},
    /// {EXISTING_SOURCES}, {NEW_ARTIFACTS}
    static let kcExpandInitial: String = {
        loadPrompt(named: "kc_expand_initial")
    }()

    /// Prose summary generation prompt for MergedCard → ResRef conversion
    /// Contains placeholders: {CARD_TYPE}, {TITLE}, {ORGANIZATION}, {TIME_PERIOD},
    /// {KEY_FACTS}, {TECHNOLOGIES}, {OUTCOMES}
    static let kcProseSummary: String = {
        loadPrompt(named: "kc_prose_summary")
    }()

    // MARK: - Document Extraction Prompts

    /// Default PDF/document extraction prompt
    static let documentExtraction: String = {
        loadPrompt(named: "document_extraction_prompt")
    }()

    /// Document summarization prompt template.
    /// Contains placeholders: {FILENAME}, {CONTENT}
    static let documentSummaryTemplate: String = {
        loadPrompt(named: "document_summary_prompt")
    }()

    /// PDF graphics extraction prompt for visual content analysis.
    /// Contains placeholder: {FILENAME}
    static let pdfGraphicsExtraction: String = {
        loadPrompt(named: "pdf_graphics_extraction")
    }()

    // MARK: - Git Agent Prompts

    /// System prompt for git repository analysis agent
    static let gitAgentSystemPrompt: String = {
        loadPrompt(named: "git_agent_system_prompt")
    }()

    /// Author filter template for git agent
    /// Contains placeholder: {AUTHOR}
    static let gitAgentAuthorFilter: String = {
        loadPrompt(named: "git_agent_author_filter")
    }()

    // MARK: - Tool Workflow Prompts

    /// Agent ready tool workflow summary
    static let agentReadyWorkflow: String = {
        loadPrompt(named: "agent_ready_workflow")
    }()

    // MARK: - Voice Primer Prompts

    /// Voice primer extraction prompt template
    /// Contains placeholder: {WRITING_SAMPLES}
    static let voicePrimerExtraction: String = {
        loadPrompt(named: "voice_primer_extraction")
    }()

    // MARK: - Card Pipeline Prompts

    /// Card inventory prompt template
    /// Contains placeholders: {DOC_ID}, {FILENAME}, {DOCUMENT_TYPE}, {CLASSIFICATION_JSON}, {EXTRACTED_CONTENT}
    static let cardInventoryTemplate: String = {
        loadPrompt(named: "card_inventory_prompt")
    }()

    /// Cross-document merge prompt template
    /// Contains placeholders: {INVENTORIES_JSON}, {TIMELINE_JSON}
    static let crossDocumentMergeTemplate: String = {
        loadPrompt(named: "cross_document_merge_prompt")
    }()

    // MARK: - Prompt Loading

    /// Loads a prompt from a resource file in the Prompts directory.
    /// - Parameter name: The filename without extension (supports .txt and .md)
    /// - Returns: The prompt content as a string
    private static func loadPrompt(named name: String) -> String {
        // Try .txt first, then .md
        // Prompts are in Resources/Prompts (consolidated location for all prompts)
        for ext in ["txt", "md"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Prompts"),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }

        // Fallback: log error and return placeholder
        Logger.error("⚠️ Failed to load prompt: \(name)")
        return "[PROMPT LOAD ERROR: \(name)]"
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
