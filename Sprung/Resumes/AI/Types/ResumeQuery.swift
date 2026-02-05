//
//  ResumeQuery.swift
//  Sprung
//
//  Provides schemas and prompt building for the clarifying questions workflow.
//
import Foundation
import PDFKit
import AppKit
import SwiftUI
@Observable class ResumeApiQuery {
    // MARK: - Properties
    /// Set this to `true` if you want to save a debug file containing the prompt text.
    var saveDebugPrompt: Bool = false

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
    let genericSystemMessage: LLMMessage = {
        let content = loadPromptTemplate(named: "discovery_generic_system")
        return LLMMessage.text(role: .system, content: content)
    }()

    // MARK: - Prompt Loading

    private static func loadPromptTemplate(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("Failed to load prompt template: \(name)", category: .ai)
            return "Error loading prompt template"
        }
        return content
    }

    private func loadPromptTemplate(named name: String) -> String {
        Self.loadPromptTemplate(named: name)
    }

    private func loadPromptTemplateWithSubstitutions(named name: String, substitutions: [String: String]) -> String {
        var template = loadPromptTemplate(named: name)
        for (key, value) in substitutions {
            template = template.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return template
    }
    // Make this var instead of let so it can be updated
    var applicant: Applicant
    var queryString: String = ""
    let res: Resume
    private let exportCoordinator: ResumeExportCoordinator
    private let allKnowledgeCards: [KnowledgeCard]
    // MARK: - Derived Properties
    var backgroundDocs: String {
        if allKnowledgeCards.isEmpty {
            Logger.debug("[ResumeQuery] No knowledge cards available")
            return "(No background documents/knowledge cards available)"
        } else {
            Logger.debug("[ResumeQuery] Including \(allKnowledgeCards.count) knowledge cards in prompt")
            return allKnowledgeCards.map { $0.title + ":\n" + $0.narrative + "\n\n" }.joined()
        }
    }
    var resumeText: String {
        res.textResume
    }
    var jobListing: String {
        return res.jobApp?.jobListingString ?? ""
    }
    // MARK: - Initialization
    init(
        resume: Resume,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfile: ApplicantProfile,
        allKnowledgeCards: [KnowledgeCard],
        saveDebugPrompt: Bool = true
    ) {
        res = resume
        self.exportCoordinator = exportCoordinator
        self.allKnowledgeCards = allKnowledgeCards
        applicant = Applicant(profile: applicantProfile)
        self.saveDebugPrompt = saveDebugPrompt
    }
    // MARK: - Prompt Building
    /// Generate prompt for clarifying questions workflow
    /// Returns resume context WITHOUT editable nodes, plus clarifying questions instructions
    @MainActor
    func clarifyingQuestionsPrompt() async -> String {
        // Get resume context WITHOUT editable nodes (clarifying questions don't need them)
        let resumeContextOnly = await clarifyingQuestionsContextString()
        // Add clarifying questions instruction
        let clarifyingQuestionsInstruction = loadPromptTemplate(named: "resume_clarifying_questions_instructions")
        return resumeContextOnly + clarifyingQuestionsInstruction
    }
    /// Generate resume context for clarifying questions (excludes editable nodes and JSON)
    /// This provides the resume text, job listing, and background docs for context
    /// but does NOT include the JSON structure or editable nodes array since clarifying questions
    /// are about gathering information, not proposing specific revisions
    @MainActor
    func clarifyingQuestionsContextString() async -> String {
        // Ensure the resume's rendered text is up-to-date
        try? await exportCoordinator.ensureFreshRenderedText(for: res)

        // Build context prompt from template
        let prompt = loadPromptTemplateWithSubstitutions(named: "resume_clarifying_questions_context", substitutions: [
            "resumeText": resumeText,
            "applicantName": applicant.name,
            "jobListing": jobListing,
            "backgroundDocs": backgroundDocs
        ])

        // If debug flag is set, save the prompt to a text file in the user's Downloads folder.
        if saveDebugPrompt {
            savePromptToDownloads(content: prompt, fileName: "clarifyingQuestionsDebug.txt")
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
        } catch {
            Logger.warning(
                "Failed to persist debug prompt to Downloads: \(error.localizedDescription)",
                category: .diagnostics
            )
        }
    }
}
