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

    // MARK: - Dependencies
    private var reviewService: ResumeReviewService?

    // MARK: - Initialization
    func initialize(llmFacade: LLMFacade) {
        reviewService = ResumeReviewService(llmFacade: llmFacade)
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
    }

    // MARK: - Private Methods
    private func resetState() {
        reviewResponseText = ""
        reviewError = nil
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
