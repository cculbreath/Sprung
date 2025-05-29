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
class ApplicationReviewService: @unchecked Sendable {
    private var currentRequestID: UUID?
    
    // MARK: - Init
    
    @MainActor
    func initialize() {
        LLMRequestService.shared.initialize()
    }

    // MARK: - Using ImageConversionService for image conversion

    // MARK: - Prompt building

    func buildPrompt(
        reviewType: ApplicationReviewType,
        jobApp: JobApp,
        resume: Resume,
        coverLetter: CoverLetter?,
        includeImage: Bool,
        customOptions: CustomApplicationReviewOptions? = nil
    ) -> String {
        var prompt = reviewType.promptTemplate()

        // Handle custom build if necessary
        if reviewType == .custom, let opt = customOptions {
            prompt = buildCustomPrompt(options: opt)
        }

        prompt = prompt.replacingOccurrences(of: "{jobPosition}", with: jobApp.jobPosition)
        prompt = prompt.replacingOccurrences(of: "{companyName}", with: jobApp.companyName)
        prompt = prompt.replacingOccurrences(of: "{jobDescription}", with: jobApp.jobDescription)

        // Cover letter text replacement.
        let coverText = coverLetter?.content ?? ""
        prompt = prompt.replacingOccurrences(of: "{coverLetterText}", with: coverText)

        // Resume text
        prompt = prompt.replacingOccurrences(of: "{resumeText}", with: resume.textRes == "" ? resume.model?.renderedResumeText ?? "" : resume.textRes)

        // Background docs placeholder
        let bgDocs = resume.enabledSources.map { "\($0.name):\n\($0.content)\n\n" }.joined()
        prompt = prompt.replacingOccurrences(of: "{backgroundDocs}", with: bgDocs)

        // Include image sentence
        prompt = prompt.replacingOccurrences(of: "{includeImage}", with: includeImage ? "I've also attached an image so you can assess its overall professionalism and design." : "")

        return prompt
    }

    private func buildCustomPrompt(options: CustomApplicationReviewOptions) -> String {
        var segments: [String] = []

        Logger.debug("🔧 [ApplicationReview] Building custom prompt")
        Logger.debug("🔧 [ApplicationReview] Include cover letter: \(options.includeCoverLetter)")
        Logger.debug("🔧 [ApplicationReview] Include resume text: \(options.includeResumeText)")
        Logger.debug("🔧 [ApplicationReview] Include resume image: \(options.includeResumeImage)")
        Logger.debug("🔧 [ApplicationReview] Include background docs: \(options.includeBackgroundDocs)")
        Logger.debug("🔧 [ApplicationReview] Custom prompt length: \(options.customPrompt.count)")

        if options.includeCoverLetter {
            segments.append("""
            Cover Letter
            ------------
            {coverLetterText}
            """)
        }

        if options.includeResumeText {
            segments.append("""
            Resume
            ------
            {resumeText}
            """)
        }

        if options.includeResumeImage {
            segments.append("{includeImage}")
        }

        if options.includeBackgroundDocs {
            segments.append("""
            Background Docs
            ---------------
            {backgroundDocs}
            """)
        }

        // Add custom prompt or a default if empty
        let finalPrompt = options.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalPrompt.isEmpty {
            Logger.warning("🔧 [ApplicationReview] Custom prompt is empty, using default")
            segments.append("Please review the above materials and provide your analysis.")
        } else {
            segments.append(finalPrompt)
        }
        
        let result = segments.joined(separator: "\n\n")
        Logger.debug("🔧 [ApplicationReview] Custom prompt built, total length: \(result.count)")
        return result
    }

    // MARK: - LLM Request (non-image handled by client, image via raw call)

    @MainActor
    func sendReviewRequest(
        reviewType: ApplicationReviewType,
        jobApp: JobApp,
        resume: Resume,
        coverLetter: CoverLetter?,
        customOptions: CustomApplicationReviewOptions? = nil,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        // Check if model supports images
        let supportsImages = LLMRequestService.shared.checkIfModelSupportsImages()
        var imageBase64: String?
        
        if supportsImages,
           reviewType != .custom || (customOptions?.includeResumeImage ?? false),
           let pdfData = resume.pdfData
        {
            imageBase64 = ImageConversionService.shared.convertPDFToBase64Image(pdfData: pdfData)
        }

        let includeImage = imageBase64 != nil

        // Build the prompt
        let prompt = buildPrompt(
            reviewType: reviewType,
            jobApp: jobApp,
            resume: resume,
            coverLetter: coverLetter,
            includeImage: includeImage,
            customOptions: customOptions
        )

        let requestID = UUID()
        currentRequestID = requestID
        
        // Add system prompt to the beginning
        let fullPrompt = "You are an expert recruiter reviewing job application packets.\n\n" + prompt

        if includeImage, let img = imageBase64 {
            // Image request requires mixed request handling
            Logger.debug("📸 [ApplicationReview] Using image-based request path")
            LLMRequestService.shared.sendMixedRequest(
                promptText: fullPrompt,
                base64Image: img,
                requestID: requestID
            ) { result in
                switch result {
                case .success(let responseWrapper):
                    Logger.debug("📥 [ApplicationReview] Received response")
                    Logger.debug("📥 [ApplicationReview] Response length: \(responseWrapper.content.count) characters")
                    onProgress(responseWrapper.content)
                    onComplete(.success("Done"))
                case .failure(let error):
                    Logger.error("❌ [ApplicationReview] Error: \(error)")
                    onComplete(.failure(error))
                }
            }
        } else {
            // Text-only request
            Logger.debug("📤 [ApplicationReview] Sending text-only request")
            Logger.debug("📤 [ApplicationReview] Review type: \(reviewType.rawValue)")
            Logger.debug("📤 [ApplicationReview] Prompt length: \(prompt.count) characters")
            
            LLMRequestService.shared.sendTextRequest(
                promptText: fullPrompt,
                model: OpenAIModelFetcher.getPreferredModelString(),
                onProgress: onProgress,
                onComplete: { result in
                    switch result {
                    case .success(_):
                        Logger.debug("📥 [ApplicationReview] Review complete")
                        onComplete(.success("Done"))
                    case .failure(let error):
                        Logger.error("❌ [ApplicationReview] Error: \(error)")
                        onComplete(.failure(error))
                    }
                }
            )
        }
    }

    // Cancel
    func cancelRequest() { 
        currentRequestID = nil 
    }
}
