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

    /// Phase 1 introductory prompt (Core Facts collection)
    static let phase1Intro: String = {
        loadPrompt(named: "phase1_intro_prompt")
    }()

    /// Phase 2 introductory prompt (Knowledge Card generation)
    static let phase2Intro: String = {
        loadPrompt(named: "phase2_intro_prompt")
    }()

    /// Phase 3 introductory prompt (Writing Corpus collection)
    static let phase3Intro: String = {
        loadPrompt(named: "phase3_intro_prompt")
    }()

    // MARK: - Knowledge Card Agent Prompts

    /// System prompt template for Knowledge Card generation agents.
    /// Contains placeholders: {TITLE}, {CARD_TYPE}, {NAME_REF}
    static let kcAgentSystemPromptTemplate: String = {
        loadPrompt(named: "kc_agent_system_prompt")
    }()

    /// Additional guidance for skill-type Knowledge Cards
    static let kcSkillCardGuidance: String = {
        loadPrompt(named: "kc_skill_card_guidance")
    }()

    /// Additional guidance for job-type Knowledge Cards
    static let kcJobCardGuidance: String = {
        loadPrompt(named: "kc_job_card_guidance")
    }()

    /// Error recovery prompt for KC agents
    static let kcErrorRecovery: String = {
        loadPrompt(named: "kc_error_recovery")
    }()

    /// Initial prompt template for KC agents
    /// Contains placeholders for card details and artifact summaries
    static let kcInitialPromptTemplate: String = {
        loadPrompt(named: "kc_initial_prompt")
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

    // MARK: - Card Pipeline Prompts

    /// Document classification prompt template
    /// Contains placeholders: {FILENAME}, {PREVIEW}
    static let documentClassificationTemplate: String = {
        loadPrompt(named: "document_classification_prompt")
    }()

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

    // MARK: - Type-Specific KC Extraction Prompts

    /// Employment card extraction prompt
    /// Contains placeholders: {TITLE}, {ORGANIZATION}, {DATE_RANGE}, {CARD_ID}, {EVIDENCE_BLOCKS_WITH_CONTENT}
    static let kcExtractionEmployment: String = {
        loadPrompt(named: "kc_extraction_employment")
    }()

    /// Skill card extraction prompt
    /// Contains placeholders: {SKILL_NAME}, {EVIDENCE_BLOCKS_WITH_CONTENT}
    static let kcExtractionSkill: String = {
        loadPrompt(named: "kc_extraction_skill")
    }()

    /// Project card extraction prompt
    /// Contains placeholders: {PROJECT_NAME}, {EVIDENCE_BLOCKS_WITH_CONTENT}
    static let kcExtractionProject: String = {
        loadPrompt(named: "kc_extraction_project")
    }()

    /// Achievement card extraction prompt
    /// Contains placeholders: {ACHIEVEMENT_TITLE}, {EVIDENCE_BLOCKS_WITH_CONTENT}
    static let kcExtractionAchievement: String = {
        loadPrompt(named: "kc_extraction_achievement")
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
