// PhysCloudResume/AI/Models/ResumeReviewService.swift

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Service for handling resume review operations with LLM
class ResumeReviewService: @unchecked Sendable {
    // MARK: - Properties
    
    /// The current request ID for tracking active requests
    private var currentRequestID: UUID?
    
    // MARK: - Initialization
    
    /// Initialize the LLM client
    @MainActor
    func initialize() {
        LLMRequestService.shared.initialize()
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
        customOptions: CustomReviewOptions? = nil,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        // Check if model supports images
        let supportsImages = LLMRequestService.shared.checkIfModelSupportsImages()
        var base64Image: String?
        
        if supportsImages,
           (reviewType != .custom && reviewType != .fixOverflow) || (customOptions?.includeResumeImage ?? false),
           let pdfData = resume.pdfData
        {
            base64Image = ImageConversionService.shared.convertPDFToBase64Image(pdfData: pdfData)
        }
        
        let includeImageInPromptText = base64Image != nil
        
        // Build the prompt based on the review type
        let promptText = PromptBuilderService.shared.buildPrompt(
            reviewType: reviewType,
            resume: resume,
            includeImage: includeImageInPromptText,
            customOptions: customOptions
        )
        
        let requestID = UUID()
        currentRequestID = requestID
        
        if includeImageInPromptText, let img = base64Image {
            // Image request requires direct API handling
            LLMRequestService.shared.sendMixedRequest(
                promptText: promptText,
                base64Image: img,
                previousResponseId: resume.previousResponseId,
                schema: nil,
                requestID: requestID
            ) { result in
                if case let .success(responseWrapper) = result {
                    resume.previousResponseId = responseWrapper.id
                    onComplete(.success(responseWrapper.content))
                } else if case let .failure(error) = result {
                    onComplete(.failure(error))
                }
            }
        } else {
            // Text-only request can use the standard LLM request
            LLMRequestService.shared.sendTextRequest(
                promptText: promptText,
                model: OpenAIModelFetcher.getPreferredModelString(),
                previousResponseId: resume.previousResponseId,
                onProgress: onProgress,
                onComplete: { result in
                    switch result {
                    case .success(let response):
                        resume.previousResponseId = response.id
                        onComplete(.success("Review complete"))
                    case .failure(let error):
                        onComplete(.failure(error))
                    }
                }
            )
        }
    }
    
    /// Sends a request to the LLM to revise skills for fitting
    /// - Parameters:
    ///   - resume: The resume containing the skills
    ///   - skillsJsonString: JSON string representation of skills
    ///   - base64Image: Base64 encoded image of the resume
    ///   - onComplete: Completion callback with result
    @MainActor
    func sendFixFitsRequest(
        resume: Resume,
        skillsJsonString: String,
        base64Image: String,
        onComplete: @escaping (Result<FixFitsResponseContainer, Error>) -> Void
    ) {
        let prompt = PromptBuilderService.shared.buildFixFitsPrompt(skillsJsonString: skillsJsonString)
        let schemaName = "fix_skills_overflow_schema"
        let schema = OverflowSchemas.fixFitsSchemaString
        
        let requestID = UUID()
        currentRequestID = requestID
        
        LLMRequestService.shared.sendMixedRequest(
            promptText: prompt,
            base64Image: base64Image,
            previousResponseId: resume.previousResponseId,
            schema: (name: schemaName, jsonString: schema),
            requestID: requestID
        ) { result in
            guard self.currentRequestID == requestID else { return }
            
            switch result {
            case let .success(responseWrapper):
                resume.previousResponseId = responseWrapper.id
                
                do {
                    guard let responseData = responseWrapper.content.data(using: .utf8) else {
                        throw NSError(domain: "ResumeReviewService", code: 1004, userInfo: [NSLocalizedDescriptionKey: "Failed to convert LLM content to Data."])
                    }
                    
                    let decodedResponse = try JSONDecoder().decode(FixFitsResponseContainer.self, from: responseData)
                    onComplete(.success(decodedResponse))
                } catch {
                    onComplete(.failure(error))
                }
                
            case let .failure(error):
                onComplete(.failure(error))
            }
        }
    }
    
    /// Sends a request to the LLM to check if content fits
    /// - Parameters:
    ///   - resume: The resume to check
    ///   - base64Image: Base64 encoded image of the resume
    ///   - onComplete: Completion callback with result
    @MainActor
    func sendContentsFitRequest(
        resume: Resume,
        base64Image: String,
        onComplete: @escaping (Result<ContentsFitResponse, Error>) -> Void
    ) {
        let prompt = PromptBuilderService.shared.buildContentsFitPrompt()
        let schemaName = "check_content_fit_schema"
        let schema = OverflowSchemas.contentsFitSchemaString
        
        let requestID = UUID()
        currentRequestID = requestID
        
        LLMRequestService.shared.sendMixedRequest(
            promptText: prompt,
            base64Image: base64Image,
            previousResponseId: resume.previousResponseId,
            schema: (name: schemaName, jsonString: schema),
            requestID: requestID
        ) { result in
            guard self.currentRequestID == requestID else { return }
            
            switch result {
            case let .success(responseWrapper):
                resume.previousResponseId = responseWrapper.id
                
                do {
                    guard let responseData = responseWrapper.content.data(using: .utf8) else {
                        throw NSError(domain: "ResumeReviewService", code: 1005, userInfo: [NSLocalizedDescriptionKey: "Failed to convert LLM content to Data for contentsFit."])
                    }
                    
                    let decodedResponse = try JSONDecoder().decode(ContentsFitResponse.self, from: responseData)
                    onComplete(.success(decodedResponse))
                } catch {
                    onComplete(.failure(error))
                }
                
            case let .failure(error):
                onComplete(.failure(error))
            }
        }
    }
    
    /// Extracts skills and expertise nodes from a resume for LLM processing
    /// - Parameter resume: The resume to extract skills from
    /// - Returns: A JSON string representing the skills and expertise
    func extractSkillsForLLM(resume: Resume) -> String? {
        return TreeNodeExtractor.shared.extractSkillsForLLM(resume: resume)
    }
    
    /// Cancels the current review request
    func cancelRequest() {
        currentRequestID = nil
        LLMRequestService.shared.cancelRequest()
    }
}