// Sprung/AI/Models/ResumeReviewService.swift
import Foundation
import PDFKit
import AppKit
import SwiftUI
/// Service for handling resume review operations with LLM
class ResumeReviewService: @unchecked Sendable {
    // MARK: - Properties
    /// The LLM service for AI operations
    private let llm: LLMFacade
    /// The query service for prompts
    private let query = ResumeReviewQuery()
    /// The current request ID for tracking active requests
    private var currentRequestID: UUID?
    private var activeStreamingHandle: LLMStreamingHandle?
    /// Initialize with LLM service
    init(llmFacade: LLMFacade) {
        self.llm = llmFacade
    }
    // MARK: - Public Methods
    /// Sends a review request to the LLM
    /// - Parameters:
    ///   - reviewType: The type of review to perform
    ///   - resume: The resume to review
    ///   - customOptions: Optional custom review options
    ///   - onProgress: Callback for progress updates (streaming)
    ///   - onComplete: Completion callback with result
    @MainActor
    func sendReviewRequest(
        reviewType: ResumeReviewType,
        resume: Resume,
        modelId: String,
        customOptions: CustomReviewOptions? = nil,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        let requestID = UUID()
        currentRequestID = requestID
        Task { @MainActor in
            do {
                // Determine if we need image input
                let needsImage = (reviewType != .custom && reviewType != .fixOverflow) ||
                    (customOptions?.includeResumeImage ?? false)
                var imageData: [Data] = []
                if needsImage, let pdfData = resume.pdfData {
                    // Convert PDF to PNG image format
                    if let base64Image = ImageConversionService.shared.convertPDFToBase64Image(pdfData: pdfData),
                       let pngData = Data(base64Encoded: base64Image) {
                        imageData = [pngData]
                    } else {
                        Logger.error("ResumeReviewService: Failed to convert PDF to image format")
                        onComplete(.failure(NSError(
                            domain: "ResumeReviewService",
                            code: 1008,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to convert PDF to image format"]
                        )))
                        return
                    }
                }
                // Build the prompt using the centralized ResumeReviewQuery
                let promptText = query.buildReviewPrompt(
                    reviewType: reviewType,
                    resume: resume,
                    includeImage: !imageData.isEmpty,
                    customOptions: customOptions
                )
                Logger.debug("🔍 ResumeReviewService: Sending review request with model: \(modelId)")
                let response: String
                if imageData.isEmpty {
                    // Text-only request
                    response = try await llm.executeText(prompt: promptText, modelId: modelId, temperature: nil)
                } else {
                    // Multimodal request
                    response = try await llm.executeTextWithImages(
                        prompt: promptText,
                        modelId: modelId,
                        images: imageData,
                        temperature: nil
                    )
                }
                // Check if request was cancelled
                guard currentRequestID == requestID else {
                    Logger.debug("ResumeReviewService: Request cancelled")
                    return
                }
                Logger.debug("✅ ResumeReviewService: Review completed successfully")
                onProgress(response)
                onComplete(.success("Done"))
            } catch {
                // Check if request was cancelled
                guard currentRequestID == requestID else {
                    Logger.debug("ResumeReviewService: Request cancelled during error handling")
                    return
                }
                Logger.error("ResumeReviewService: Review failed: \(error.localizedDescription)")
                onComplete(.failure(error))
            }
        }
    }
    /// Cancels the current review request
    func cancelRequest() {
        currentRequestID = nil
        activeStreamingHandle?.cancel()
        activeStreamingHandle = nil
        Logger.debug("ResumeReviewService: Request cancelled by setting currentRequestID to nil")
    }
}
