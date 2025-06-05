//
//  ApplicationReviewService.swift
//  PhysCloudResume
//
//  Created by OpenAI Assistant on 5/11/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Service responsible for sending application packet reviews (cover letter + resume)
@MainActor
class ApplicationReviewService: @unchecked Sendable {
    // MARK: - Properties
    
    /// The LLM service for AI operations
    private let llmService: LLMService
    
    /// The query service for prompts
    private let query = ApplicationReviewQuery()
    
    /// The current request ID for tracking active requests
    private var currentRequestID: UUID?
    
    // MARK: - Initialization
    
    /// Initialize with LLM service
    init(llmService: LLMService = LLMService.shared) {
        self.llmService = llmService
    }
    
    /// Initialize the LLM client
    func initialize() {
        // No longer needed - LLMService manages its own initialization
        Logger.debug("ApplicationReviewService: Initialization delegated to LLMService")
    }

    // MARK: - Deprecated Legacy Methods (kept for compatibility)
    
    /// Legacy method kept for compatibility - delegates to ApplicationReviewQuery
    func buildPrompt(
        reviewType: ApplicationReviewType,
        jobApp: JobApp,
        resume: Resume,
        coverLetter: CoverLetter?,
        includeImage: Bool,
        customOptions: CustomApplicationReviewOptions? = nil
    ) -> String {
        return query.buildReviewPrompt(
            reviewType: reviewType,
            jobApp: jobApp,
            resume: resume,
            coverLetter: coverLetter,
            includeImage: includeImage,
            customOptions: customOptions
        )
    }

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
        // Determine if we should include image based on review type and options
        let shouldIncludeImage = (reviewType != .custom) || (customOptions?.includeResumeImage ?? false)
        var imageData: [Data] = []
        
        if shouldIncludeImage, let pdfData = resume.pdfData {
            imageData = [pdfData]
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
                    response = try await llmService.executeWithImages(
                        prompt: fullPrompt,
                        modelId: modelId,
                        images: imageData
                    )
                } else {
                    // Text-only request
                    Logger.debug("📤 [ApplicationReview] Sending text-only request")
                    response = try await llmService.execute(
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
            llmService.cancelAllRequests()
            Logger.debug("🚫 [ApplicationReview] Cancelled request: \(requestID)")
        }
        currentRequestID = nil
    }
}
