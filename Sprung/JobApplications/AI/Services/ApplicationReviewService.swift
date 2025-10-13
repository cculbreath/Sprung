//
//  ApplicationReviewService.swift
//  Sprung
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Service responsible for sending application packet reviews (cover letter + resume)
@MainActor
class ApplicationReviewService: @unchecked Sendable {
    // MARK: - Properties
    
    /// The LLM facade for AI operations
    private let llm: LLMFacade
    private let exportCoordinator: ResumeExportCoordinator
    
    /// The query service for prompts
    private let query = ApplicationReviewQuery()
    
    /// The current request ID for tracking active requests
    private var currentRequestID: UUID?
    
    // MARK: - Initialization
    
    /// Initialize with LLM service
    init(llmFacade: LLMFacade, exportCoordinator: ResumeExportCoordinator) {
        self.llm = llmFacade
        self.exportCoordinator = exportCoordinator
    }
    

    // MARK: - Core Review Operations

    // MARK: - LLM Request (non-image handled by client, image via raw call)

    func sendReviewRequest(
        reviewType: ApplicationReviewType,
        jobApp: JobApp,
        resume: Resume,
        coverLetter: CoverLetter?,
        modelId: String,
        customOptions: CustomApplicationReviewOptions? = nil,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        // Ensure fresh text resume is rendered before making LLM request
        Task {
            do {
                try await exportCoordinator.ensureFreshRenderedText(for: resume)
                await performReviewRequest(
                    reviewType: reviewType,
                    jobApp: jobApp,
                    resume: resume,
                    coverLetter: coverLetter,
                    modelId: modelId,
                    customOptions: customOptions,
                    onProgress: onProgress,
                    onComplete: onComplete
                )
            } catch {
                Logger.error("ApplicationReviewService: Failed to render fresh text: \(error)")
                onComplete(.failure(error))
            }
        }
    }
    
    private func performReviewRequest(
        reviewType: ApplicationReviewType,
        jobApp: JobApp,
        resume: Resume,
        coverLetter: CoverLetter?,
        modelId: String,
        customOptions: CustomApplicationReviewOptions? = nil,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) async {
        // Determine if we should include image based on review type and options
        let shouldIncludeImage = (reviewType != .custom) || (customOptions?.includeResumeImage ?? false)
        var imageData: [Data] = []
        
        if shouldIncludeImage, let pdfData = resume.pdfData {
            // Convert PDF to PNG image format
            if let base64Image = ImageConversionService.shared.convertPDFToBase64Image(pdfData: pdfData),
               let pngData = Data(base64Encoded: base64Image) {
                imageData = [pngData]
            } else {
                Logger.error("ApplicationReviewService: Failed to convert PDF to image format")
                onComplete(.failure(NSError(domain: "ApplicationReviewService", code: 1008, userInfo: [NSLocalizedDescriptionKey: "Failed to convert PDF to image format"])))
                return
            }
        }

        // Build the prompt using ApplicationReviewQuery
        let fullPrompt = query.systemPrompt() + "\n\n" + query.buildReviewPrompt(
            reviewType: reviewType,
            jobApp: jobApp,
            resume: resume,
            coverLetter: coverLetter,
            includeImage: !imageData.isEmpty,
            customOptions: customOptions
        )

        let requestID = UUID()
        currentRequestID = requestID
        
        Logger.debug("📤 [ApplicationReview] Starting review request")
        Logger.debug("📤 [ApplicationReview] Review type: \(reviewType.rawValue)")
        Logger.debug("📤 [ApplicationReview] Model: \(modelId)")
        Logger.debug("📤 [ApplicationReview] Prompt length: \(fullPrompt.count) characters")
        Logger.debug("📤 [ApplicationReview] Image included: \(!imageData.isEmpty)")

        Task {
            do {
                let response: String
                
                if !imageData.isEmpty {
                    // Image request requires multimodal handling
                    Logger.debug("📸 [ApplicationReview] Using image-based request path")
                    response = try await llm.executeTextWithImages(
                        prompt: fullPrompt,
                        modelId: modelId,
                        images: imageData
                    )
                } else {
                    // Text-only request
                    Logger.debug("📤 [ApplicationReview] Sending text-only request")
                    response = try await llm.executeText(
                        prompt: fullPrompt,
                        modelId: modelId
                    )
                }
                
                // Check if request was cancelled
                guard currentRequestID == requestID else {
                    Logger.debug("📤 [ApplicationReview] Request cancelled")
                    return
                }
                
                Logger.debug("📥 [ApplicationReview] Review complete")
                Logger.debug("📥 [ApplicationReview] Response length: \(response.count) characters")
                
                // Stream the response for UI consistency
                onProgress(response)
                onComplete(.success("Done"))
                
            } catch {
                // Check if request was cancelled
                guard currentRequestID == requestID else {
                    Logger.debug("📤 [ApplicationReview] Request cancelled during error handling")
                    return
                }
                
                Logger.error("❌ [ApplicationReview] Error: \(error)")
                onComplete(.failure(error))
            }
        }
    }

    /// Cancel the current request
    func cancelRequest() {
        if let requestID = currentRequestID {
            llm.cancelAllRequests()
            Logger.debug("🚫 [ApplicationReview] Cancelled request: \(requestID)")
        }
        currentRequestID = nil
    }
}
