// Sprung/Resumes/AI/Views/ResumeReviewViewModel.swift
import Foundation
import SwiftUI

/// UI state for the advisory AI resume review sheet. Every review type is
/// read-only analysis (streamed markdown) — tree mutations belong exclusively
/// to the revision agent's reviewed propose_changes flow.
@MainActor
@Observable
class ResumeReviewViewModel {
    // MARK: - State Properties
    private(set) var reviewResponseText: String = ""
    private(set) var isProcessing: Bool = false
    private(set) var reviewError: String?
    /// When the currently-displayed markdown was saved onto the resume (nil when
    /// showing a fresh, unsaved placeholder or an error). Drives the "Saved …"
    /// caption so the user can tell a revisited review from a just-run one.
    private(set) var savedReviewDate: Date?
    private(set) var savedReviewType: String?

    // MARK: - Dependencies
    private var reviewService: ResumeReviewService?

    // MARK: - Initialization
    func initialize(llmFacade: LLMFacade) {
        reviewService = ResumeReviewService(llmFacade: llmFacade)
    }

    /// Populate the sheet with the last review persisted on this resume (if any),
    /// so reopening the Optimize sheet shows the previous analysis and its date
    /// rather than a blank slate. Called on appear.
    func loadStoredReview(from resume: Resume) {
        guard let markdown = resume.lastReviewMarkdown, !markdown.isEmpty else { return }
        reviewResponseText = markdown
        savedReviewDate = resume.lastReviewDate
        savedReviewType = resume.lastReviewType
    }

    // MARK: - Public Methods
    func handleSubmit(
        reviewType: ResumeReviewType,
        resume: Resume,
        selectedModel: String,
        knowledgeCards: [KnowledgeCard],
        customOptions: CustomReviewOptions?
    ) {
        resetState()
        // No model configured → surface the configuration error; never substitute a default.
        guard !selectedModel.trimmingCharacters(in: .whitespaces).isEmpty else {
            let error = ModelConfigurationError.modelNotConfigured(
                settingKey: "resumeReviewSelectedModel",
                operationName: "Resume Review"
            )
            reviewError = [error.localizedDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
            return
        }
        performReview(
            reviewType: reviewType,
            resume: resume,
            selectedModel: selectedModel,
            knowledgeCards: knowledgeCards,
            customOptions: customOptions
        )
    }

    func cancelRequest() {
        reviewService?.cancelRequest()
        isProcessing = false
    }

    func resetOnReviewTypeChange() {
        reviewResponseText = ""
        isProcessing = false
        reviewError = nil
        savedReviewDate = nil
        savedReviewType = nil
    }

    // MARK: - Private Methods
    private func resetState() {
        reviewResponseText = ""
        reviewError = nil
        savedReviewDate = nil
        savedReviewType = nil
    }

    /// Persist the completed review onto the resume so it survives dismiss and a
    /// relaunch, and update the caption metadata to match.
    private func persistReview(_ markdown: String, resume: Resume, reviewType: ResumeReviewType) {
        guard !markdown.isEmpty else { return }
        let now = Date()
        resume.lastReviewMarkdown = markdown
        resume.lastReviewDate = now
        resume.lastReviewType = reviewType.rawValue
        savedReviewDate = now
        savedReviewType = reviewType.rawValue
        do {
            try resume.modelContext?.save()
        } catch {
            Logger.error("ResumeReviewViewModel: Failed to persist last review: \(error.localizedDescription)")
        }
    }

    private func performReview(
        reviewType: ResumeReviewType,
        resume: Resume,
        selectedModel: String,
        knowledgeCards: [KnowledgeCard],
        customOptions: CustomReviewOptions?
    ) {
        isProcessing = true
        reviewResponseText = "Submitting request..."
        reviewService?.sendReviewRequest(
            reviewType: reviewType,
            resume: resume,
            modelId: selectedModel,
            knowledgeCards: knowledgeCards,
            customOptions: reviewType == .custom ? customOptions : nil,
            onProgress: { [weak self] contentChunk in
                Task { @MainActor in
                    guard let self = self else { return }
                    if self.reviewResponseText == "Submitting request..." {
                        self.reviewResponseText = ""
                    }
                    self.reviewResponseText += contentChunk
                }
            },
            onComplete: { [weak self] result in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isProcessing = false
                    switch result {
                    case let .success(finalMessage):
                        if self.reviewResponseText == "Submitting request..." || self.reviewResponseText.isEmpty {
                            self.reviewResponseText = finalMessage
                        }
                        if self.reviewResponseText.isEmpty {
                            self.reviewResponseText = "Review complete. No specific feedback provided."
                        }
                        self.persistReview(self.reviewResponseText, resume: resume, reviewType: reviewType)
                    case let .failure(error):
                        self.handleReviewError(error)
                        if self.reviewResponseText == "Submitting request..." || !self.reviewResponseText.isEmpty {
                            self.reviewResponseText = ""
                        }
                    }
                }
            }
        )
    }

    private func handleReviewError(_ error: Error) {
        if let nsError = error as NSError? {
            if nsError.domain == "OpenAIAPI" {
                reviewError = "API Error: \(nsError.localizedDescription)"
            } else if let errorInfo = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                reviewError = "Error: \(errorInfo)\nPlease try again or select a different model in Settings."
            } else {
                reviewError = "Error: \(error.localizedDescription)"
            }
        } else {
            reviewError = "Error: \(error.localizedDescription)"
        }
    }
}
