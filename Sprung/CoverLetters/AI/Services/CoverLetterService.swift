//
//  CoverLetterService.swift
//  Sprung
//
//  Created on 6/5/2025
//
//  Service for cover letter generation and revision using unified LLMService.
//  Every request is self-contained: prompts are rebuilt deterministically from
//  the letter's persisted context (voice + job + resume + draft) on each call,
//  so generation and revision survive app restarts and run safely in parallel.
import Foundation
import SwiftUI
@MainActor
@Observable
final class CoverLetterService {
    // MARK: - Properties
    private let llmFacade: LLMFacade
    private let exportCoordinator: ResumeExportCoordinator
    private let applicantProfileStore: ApplicantProfileStore
    private let coverRefStore: CoverRefStore
    // MARK: - Initialization
    init(
        llmFacade: LLMFacade,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfileStore: ApplicantProfileStore,
        coverRefStore: CoverRefStore
    ) {
        self.llmFacade = llmFacade
        self.exportCoordinator = exportCoordinator
        self.applicantProfileStore = applicantProfileStore
        self.coverRefStore = coverRefStore
    }
    // MARK: - Cover Letter Generation
    /// Generate a new cover letter from the toolbar (handles creation and management)
    /// - Parameters:
    ///   - jobApp: The job application to generate a cover letter for
    ///   - resume: The resume to use for context
    ///   - modelId: The model ID to use for generation
    ///   - coverLetterStore: The store to create the cover letter in
    ///   - selectedRefs: The selected cover references to include
    ///   - knowledgeCards: Knowledge cards to include in the prompt
    ///   - knowledgeCardInclusion: The knowledge card inclusion mode
    ///   - selectedKnowledgeCardIds: IDs of selected knowledge cards
    ///   - dossierContext: Optional candidate dossier context
    func generateNewCoverLetter(
        jobApp: JobApp,
        resume: Resume,
        modelId: String,
        coverLetterStore: CoverLetterStore,
        selectedRefs: [CoverRef],
        knowledgeCards: [KnowledgeCard],
        knowledgeCardInclusion: KnowledgeCardInclusion,
        selectedKnowledgeCardIds: Set<String>,
        dossierContext: String?
    ) async throws {
        // Create a new cover letter
        let newCoverLetter = coverLetterStore.create(jobApp: jobApp)
        // Set initial properties
        newCoverLetter.content = ""
        newCoverLetter.setEditableName("Generating...")
        newCoverLetter.generated = false
        newCoverLetter.knowledgeCardInclusion = knowledgeCardInclusion
        newCoverLetter.selectedKnowledgeCardIds = selectedKnowledgeCardIds
        newCoverLetter.enabledRefs = selectedRefs
        // Store generation metadata (snapshot of sources and settings at generation time)
        newCoverLetter.generationSources = selectedRefs
        // Set it as the selected cover letter
        jobApp.selectedCover = newCoverLetter
        do {
            // Generate the content
            _ = try await generateCoverLetter(
                coverLetter: newCoverLetter,
                resume: resume,
                modelId: modelId,
                knowledgeCards: knowledgeCards,
                dossierContext: dossierContext
            )
            Logger.debug("✅ Cover letter generated successfully")
        } catch {
            // Clean up the failed cover letter
            coverLetterStore.deleteLetter(newCoverLetter)
            throw error
        }
    }
    /// Generate a new cover letter using AI
    /// - Parameters:
    ///   - coverLetter: The cover letter to generate content for
    ///   - resume: The resume to use for context
    ///   - modelId: The model ID to use for generation
    ///   - knowledgeCards: Knowledge cards to include in the prompt
    ///   - dossierContext: Optional candidate dossier context
    /// - Returns: The generated cover letter content
    func generateCoverLetter(
        coverLetter: CoverLetter,
        resume: Resume,
        modelId: String,
        knowledgeCards: [KnowledgeCard] = [],
        dossierContext: String? = nil
    ) async throws -> String {
        // Ensure cover letter has an associated job application
        guard let jobApp = coverLetter.jobApp else {
            Logger.error("🚨 Cover letter generation requested without job application (letter id: \(coverLetter.id))", category: .ai)
            throw NSError(
                domain: "CoverLetterService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to generate a cover letter. Please choose a job application first."]
            )
        }
        // Create CoverLetterQuery for centralized prompt management.
        // The voice block is built from the writing samples actually selected
        // for this letter, not a global default list.
        let query = CoverLetterQuery(
            coverLetter: coverLetter,
            resume: resume,
            jobApp: jobApp,
            exportCoordinator: exportCoordinator,
            applicantProfile: applicantProfileStore.currentProfile(),
            writersVoice: CoverLetterVoiceContext.build(
                selectedRefs: coverLetter.enabledRefs,
                allRefs: coverRefStore.storedCoverRefs
            ),
            knowledgeCards: knowledgeCards,
            dossierContext: dossierContext,
            saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
        )
        let prompt = try await query.generationPrompt()
        let response = try await llmFacade.executeText(prompt: prompt, modelId: modelId)
        let content = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw NSError(
                domain: "CoverLetterService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The model returned an empty cover letter. Try again or choose a different model."]
            )
        }
        // Update cover letter
        updateCoverLetter(coverLetter, with: content, modelId: modelId, isRevision: false)
        return content
    }
    // MARK: - Cover Letter Revision
    /// Revise an existing cover letter based on feedback. The request is fully
    /// self-contained — no conversation state is required or kept.
    /// - Parameters:
    ///   - coverLetter: The cover letter to revise
    ///   - resume: The resume to use for context
    ///   - modelId: The model ID to use for revision
    ///   - feedback: Optional custom feedback
    ///   - editorPrompt: The type of revision to perform
    /// - Returns: The revised cover letter content
    func reviseCoverLetter(
        coverLetter: CoverLetter,
        resume: Resume,
        modelId: String,
        feedback: String? = nil,
        editorPrompt: CoverLetterPrompts.EditorPrompts = .improve
    ) async throws -> String {
        // Ensure cover letter has an associated job application
        guard let jobApp = coverLetter.jobApp else {
            Logger.error("🚨 Cover letter revision requested without job application (letter id: \(coverLetter.id))", category: .ai)
            throw NSError(
                domain: "CoverLetterService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to revise this cover letter because no job application is selected."]
            )
        }
        // Create CoverLetterQuery for centralized prompt management
        let query = CoverLetterQuery(
            coverLetter: coverLetter,
            resume: resume,
            jobApp: jobApp,
            exportCoordinator: exportCoordinator,
            applicantProfile: applicantProfileStore.currentProfile(),
            writersVoice: CoverLetterVoiceContext.build(
                selectedRefs: coverLetter.enabledRefs,
                allRefs: coverRefStore.storedCoverRefs
            ),
            saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
        )
        let prompt = try await query.revisionPrompt(
            feedback: feedback ?? "",
            editorPrompt: editorPrompt
        )
        let response = try await llmFacade.executeText(prompt: prompt, modelId: modelId)
        let content = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw NSError(
                domain: "CoverLetterService",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "The model returned an empty revision. Try again or choose a different model."]
            )
        }
        // Update cover letter
        updateCoverLetter(coverLetter, with: content, modelId: modelId, isRevision: true)
        return content
    }
    // MARK: - Helper Methods
    /// Update cover letter with generated content
    private func updateCoverLetter(
        _ coverLetter: CoverLetter,
        with content: String,
        modelId: String,
        isRevision: Bool
    ) {
        // Update the cover letter with the response
        coverLetter.content = content
        coverLetter.generated = true
        coverLetter.moddedDate = Date()
        coverLetter.generationModel = modelId
        let formattedModel = AIModels.friendlyModelName(for: modelId) ?? modelId
        // Naming logic update:
        if isRevision {
            // For revisions, append the revision type if it's not present
            let revisionType = coverLetter.editorPrompt.operation.rawValue
            let nameBase = coverLetter.editableName
            // Only append the revision type if it's not already there
            if !nameBase.contains(revisionType) {
                coverLetter.setEditableName(nameBase + ", " + revisionType)
            }
        } else {
            // This is a fresh generation of content (not a revision)
            // Get or create an appropriate option letter
            let optionLetter: String
            if coverLetter.optionLetter.isEmpty {
                // No existing option letter, use the next available letter
                optionLetter = coverLetter.getNextOptionLetter()
            } else {
                // Already has an option letter, preserve it
                optionLetter = coverLetter.optionLetter
            }
            // Create a descriptive suffix with model and resume background info
            var nameSuffix = formattedModel
            if coverLetter.knowledgeCardInclusion != .none {
                nameSuffix += " with KC"
            }
            // Set the full name with the "Option X: description" format
            coverLetter.name = "Option \(optionLetter): \(nameSuffix)"
        }
    }
}
