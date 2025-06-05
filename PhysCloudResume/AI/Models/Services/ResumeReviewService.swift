// PhysCloudResume/AI/Models/ResumeReviewService.swift

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Service for handling resume review operations with LLM
class ResumeReviewService: @unchecked Sendable {
    // MARK: - Properties
    
    /// The LLM service for AI operations
    private let llmService: LLMService
    
    /// The query service for prompts
    private let query = ResumeReviewQuery()
    
    /// The current request ID for tracking active requests
    private var currentRequestID: UUID?
    
    /// Initialize with LLM service
    init(llmService: LLMService) {
        self.llmService = llmService
    }
    
    // MARK: - Initialization
    
    /// Initialize the LLM client
    @MainActor
    func initialize() {
        // No longer needed - LLMService manages its own initialization
        Logger.debug("ResumeReviewService: Initialization delegated to LLMService")
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
                let needsImage = (reviewType != .custom && reviewType != .fixOverflow) || (customOptions?.includeResumeImage ?? false)
                var imageData: [Data] = []
                
                if needsImage, let pdfData = resume.pdfData {
                    imageData = [pdfData]
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
                    response = try await llmService.execute(
                        prompt: promptText,
                        modelId: modelId
                    )
                } else {
                    // Multimodal request  
                    response = try await llmService.executeWithImages(
                        prompt: promptText,
                        modelId: modelId,
                        images: imageData
                    )
                }
                
                // Check if request was cancelled
                guard currentRequestID == requestID else {
                    Logger.debug("ResumeReviewService: Request cancelled")
                    return
                }
                
                Logger.debug("✅ ResumeReviewService: Review completed successfully")
                onComplete(.success(response))
                
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
    
    /// Sends a request to the LLM to revise skills for fitting
    /// - Parameters:
    ///   - resume: The resume containing the skills
    ///   - skillsJsonString: JSON string representation of skills
    ///   - base64Image: Base64 encoded image of the resume
    ///   - overflowLineCount: Number of lines overflowing from previous contentsFit check
    ///   - allowEntityMerge: Whether to allow merging of redundant entries
    ///   - onComplete: Completion callback with result
    @MainActor
    func sendFixFitsRequest(
        resume: Resume,
        skillsJsonString: String,
        base64Image: String,
        overflowLineCount: Int = 0,
        modelId: String,
        allowEntityMerge: Bool = false,
        onComplete: @escaping (Result<FixFitsResponseContainer, Error>) -> Void
    ) {
        let requestID = UUID()
        currentRequestID = requestID
        
        let provider = AIModels.providerForModel(modelId)
        
        Task { @MainActor in
            do {
                Logger.debug("🔍 ResumeReviewService: Sending fix fits request with model: \(modelId)")
                Logger.debug("🔍 Skills JSON being sent to LLM: \(skillsJsonString.prefix(500))...")
                Logger.debug("🔍 Using allowEntityMerge: \(allowEntityMerge), overflowLineCount: \(overflowLineCount)")
                
                let response: FixFitsResponseContainer
                
                // Special handling for Grok models - use text-only approach
                if provider == AIModels.Provider.grok {
                    Logger.debug("Using Grok text-only approach for fix fits request")
                    
                    // Build specialized prompt for Grok that doesn't require image analysis
                    let grokPrompt = query.buildGrokFixFitsPrompt(
                        skillsJsonString: skillsJsonString, 
                        overflowLineCount: overflowLineCount, 
                        allowEntityMerge: allowEntityMerge
                    )
                    
                    // Text-only structured request for Grok
                    response = try await llmService.executeStructured(
                        prompt: grokPrompt,
                        modelId: modelId,
                        responseType: FixFitsResponseContainer.self
                    )
                } else {
                    Logger.debug("Using standard image-based approach for fix fits request")
                    
                    // Standard approach for other models (OpenAI, Claude, Gemini)
                    let prompt = query.buildFixFitsPrompt(
                        skillsJsonString: skillsJsonString, 
                        allowEntityMerge: allowEntityMerge
                    )
                    
                    // Convert base64Image back to Data for LLMService
                    guard let imageData = Data(base64Encoded: base64Image) else {
                        throw NSError(domain: "ResumeReviewService", code: 1005, userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 image data"])
                    }
                    
                    // Multimodal structured request
                    response = try await llmService.executeStructuredWithImages(
                        prompt: prompt,
                        modelId: modelId,
                        images: [imageData],
                        responseType: FixFitsResponseContainer.self
                    )
                }
                
                // Check if request was cancelled
                guard currentRequestID == requestID else {
                    Logger.debug("ResumeReviewService: Fix fits request cancelled")
                    return
                }
                
                Logger.debug("✅ ResumeReviewService: Fix fits request completed successfully")
                onComplete(.success(response))
                
            } catch {
                // Check if request was cancelled
                guard currentRequestID == requestID else {
                    Logger.debug("ResumeReviewService: Fix fits request cancelled during error handling")
                    return
                }
                
                Logger.error("ResumeReviewService: Fix fits request failed: \(error.localizedDescription)")
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
        modelId: String,
        onComplete: @escaping (Result<ContentsFitResponse, Error>) -> Void
    ) {
        let requestID = UUID()
        currentRequestID = requestID
        
        Task { @MainActor in
            do {
                Logger.debug("🔍 ResumeReviewService: Sending contents fit request with model: \(modelId)")
                
                // Build the prompt using the centralized ResumeReviewQuery
                let prompt = query.buildContentsFitPrompt()
                Logger.debug("ResumeReviewService: ContentsFit prompt:\n\(prompt)")
                
                // Convert base64Image back to Data for LLMService
                guard let imageData = Data(base64Encoded: base64Image) else {
                    throw NSError(domain: "ResumeReviewService", code: 1006, userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 image data for contents fit check"])
                }
                
                // Multimodal structured request
                let response = try await llmService.executeStructuredWithImages(
                    prompt: prompt,
                    modelId: modelId,
                    images: [imageData],
                    responseType: ContentsFitResponse.self
                )
                
                // Check if request was cancelled
                guard currentRequestID == requestID else {
                    Logger.debug("ResumeReviewService: Contents fit request cancelled")
                    return
                }
                
                Logger.debug("✅ ResumeReviewService: Contents fit check completed successfully: contentsFit=\(response.contentsFit)")
                onComplete(.success(response))
                
            } catch {
                // Check if request was cancelled
                guard currentRequestID == requestID else {
                    Logger.debug("ResumeReviewService: Contents fit request cancelled during error handling")
                    return
                }
                
                Logger.error("ResumeReviewService: Contents fit request failed: \(error.localizedDescription)")
                
                // For backward compatibility, provide a fallback response
                Logger.debug("Defaulting to contentsFit:false to continue iterations")
                onComplete(.success(ContentsFitResponse(contentsFit: false, overflowLineCount: 0)))
            }
        }
    }
    
    /// Extracts skills and expertise nodes from a resume for LLM processing
    /// - Parameter resume: The resume to extract skills from
    /// - Returns: A JSON string representing the skills and expertise
    func extractSkillsForLLM(resume: Resume) -> String? {
        return TreeNodeExtractor.shared.extractSkillsForLLM(resume: resume)
    }
    
    /// Extracts skills for fix overflow operation with bundled title/description
    /// - Parameter resume: The resume to extract skills from
    /// - Returns: A JSON string representing the bundled skills
    func extractSkillsForFixOverflow(resume: Resume) -> String? {
        return TreeNodeExtractor.shared.extractSkillsForFixOverflow(resume: resume)
    }
    
    /// Sends a request to reorder skills based on job relevance
    /// - Parameters:
    ///   - resume: The resume containing the skills
    ///   - appState: The application state for creating the LLM client
    ///   - modelId: The model to use for skill reordering
    ///   - onComplete: Completion callback with result
    @MainActor
    func sendReorderSkillsRequest(
        resume: Resume,
        appState: AppState,
        modelId: String,
        onComplete: @escaping (Result<ReorderSkillsResponseContainer, Error>) -> Void
    ) {
        guard let jobApp = resume.jobApp else {
            onComplete(.failure(NSError(domain: "ResumeReviewService", code: 1010, userInfo: [NSLocalizedDescriptionKey: "No job application associated with this resume."])))
            return
        }
        
        Logger.debug("ResumeReviewService: sendReorderSkillsRequest called (using new SkillReorderService)")
        
        Task { @MainActor in
            do {
                let service = SkillReorderService(llmService: llmService)
                
                let reorderedNodes = try await service.fetchReorderedSkills(
                    resume: resume,
                    jobDescription: jobApp.jobDescription,
                    modelId: modelId
                )
                
                let responseContainer = ReorderSkillsResponseContainer(reorderedSkillsAndExpertise: reorderedNodes)
                onComplete(.success(responseContainer))
            } catch {
                Logger.error("SkillReorderService error: \(error.localizedDescription)")
                onComplete(.failure(error))
            }
        }
    }
    
    /// Cancels the current review request
    func cancelRequest() {
        currentRequestID = nil
        Logger.debug("ResumeReviewService: Request cancelled by setting currentRequestID to nil")
    }
    
    // MARK: - Helper Methods
    
    /// Extracts overflow line count from JSON content string
    /// - Parameter content: The JSON content string
    /// - Returns: The overflow line count, or nil if not found
    private func extractOverflowLineCount(from content: String) -> Int? {
        // Try to find overflow_line_count in the JSON string
        let patterns = [
            "\"overflow_line_count\"\\s*:\\s*(\\d+)",
            "\"overflow_line_count\":(\\d+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
               let numberRange = Range(match.range(at: 1), in: content) {
                let numberString = String(content[numberRange])
                return Int(numberString)
            }
        }
        
        return nil
    }
}