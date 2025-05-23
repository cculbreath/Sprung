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
                requestID: requestID
            ) { result in
                if case let .success(responseWrapper) = result {
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
                onProgress: onProgress,
                onComplete: { result in
                    switch result {
                    case .success(_):
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
    ///   - overflowLineCount: Number of lines overflowing from previous contentsFit check
    ///   - onComplete: Completion callback with result
    @MainActor
    func sendFixFitsRequest(
        resume: Resume,
        skillsJsonString: String,
        base64Image: String,
        overflowLineCount: Int = 0,
        onComplete: @escaping (Result<FixFitsResponseContainer, Error>) -> Void
    ) {
        _ = resume // Unused parameter
        let currentModel = OpenAIModelFetcher.getPreferredModelString()
        let provider = AIModels.providerForModel(currentModel)
        
        let requestID = UUID()
        currentRequestID = requestID
        
        // Special handling for Grok models - use text-only approach
        if provider == AIModels.Provider.grok {
            Logger.debug("Using Grok text-only approach for fix fits request with \(overflowLineCount) overflow lines")
            
            // Build specialized prompt for Grok that doesn't require image analysis
            let grokPrompt = PromptBuilderService.shared.buildGrokFixFitsPrompt(skillsJsonString: skillsJsonString, overflowLineCount: overflowLineCount)
            
            LLMRequestService.shared.sendStructuredMixedRequest(
                promptText: grokPrompt,
                base64Image: nil,  // No image for Grok
                responseType: FixFitsResponseContainer.self,
                jsonSchema: nil,
                requestID: requestID
            ) { result in
                guard self.currentRequestID == requestID else { return }
                self.handleFixFitsResponse(result: result, onComplete: onComplete)
            }
        } else {
            Logger.debug("Using standard image-based approach for fix fits request")
            
            // Standard approach for other models (OpenAI, Claude, Gemini)
            let prompt = PromptBuilderService.shared.buildFixFitsPrompt(skillsJsonString: skillsJsonString)
            
            LLMRequestService.shared.sendStructuredMixedRequest(
                promptText: prompt,
                base64Image: base64Image,
                responseType: FixFitsResponseContainer.self,
                jsonSchema: nil,
                requestID: requestID
            ) { result in
                guard self.currentRequestID == requestID else { return }
                self.handleFixFitsResponse(result: result, onComplete: onComplete)
            }
        }
    }
    
    /// Handles the response from a fix fits request (shared logic)
    /// - Parameters:
    ///   - result: The result from the LLM request
    ///   - onComplete: The completion callback
    private func handleFixFitsResponse(
        result: Result<ResponsesAPIResponse, Error>,
        onComplete: @escaping (Result<FixFitsResponseContainer, Error>) -> Void
    ) {
        switch result {
        case let .success(responseWrapper):
            
            do {
                // Get detailed information about the response for debugging
                Logger.debug("Response ID: \(responseWrapper.id)")
                Logger.debug("Response Model: \(responseWrapper.model)")
                
                let content = responseWrapper.content
                Logger.debug("Content from wrapper: \(content.prefix(100))...")
                
                guard let responseData = content.data(using: .utf8) else {
                    throw NSError(domain: "ResumeReviewService", code: 1004, userInfo: [NSLocalizedDescriptionKey: "Failed to convert LLM content to Data."])
                }
                
                // Log the JSON for debugging
                Logger.debug("FixFits response JSON: \(content)")
                
                // First try the standard JSON decoder
                do {
                    let decodedResponse = try JSONDecoder().decode(FixFitsResponseContainer.self, from: responseData)
                    onComplete(.success(decodedResponse))
                } catch let decodingError {
                    Logger.debug("Standard JSON decoding failed: \(decodingError.localizedDescription)")
                    
                    // If standard decoding fails, try a more lenient approach using JSONSerialization
                    do {
                        if let jsonObject = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                           let skillsArray = jsonObject["revised_skills_and_expertise"] as? [[String: Any]] {
                            
                            // Convert to our model manually
                            var revisedNodes: [RevisedSkillNode] = []
                            
                            for item in skillsArray {
                                if let id = item["id"] as? String,
                                   let newValue = item["newValue"] as? String,
                                   let originalValue = item["originalValue"] as? String,
                                   let treePath = item["treePath"] as? String,
                                   let isTitleNode = item["isTitleNode"] as? Bool {
                                    
                                    let node = RevisedSkillNode(
                                        id: id,
                                        newValue: newValue,
                                        originalValue: originalValue,
                                        treePath: treePath,
                                        isTitleNode: isTitleNode
                                    )
                                    revisedNodes.append(node)
                                }
                            }
                            
                            if !revisedNodes.isEmpty {
                                // If we parsed something, return it
                                onComplete(.success(FixFitsResponseContainer(revisedSkillsAndExpertise: revisedNodes)))
                                return
                            }
                        }
                        
                        // Couldn't handle it with manual parsing either
                        throw decodingError
                    } catch {
                        // All parsing failed, log full error details
                        Logger.debug("Error decoding FixFitsResponseContainer: \(error.localizedDescription)")
                        Logger.debug("Raw JSON: \(content)")
                        onComplete(.failure(error))
                    }
                }
            } catch {
                Logger.debug("Error decoding FixFitsResponseContainer: \(error.localizedDescription)")
                onComplete(.failure(error))
            }
            
        case let .failure(error):
            onComplete(.failure(error))
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
        _ = resume // Unused parameter
        Logger.debug("ResumeReviewService: sendContentsFitRequest called")
        let prompt = PromptBuilderService.shared.buildContentsFitPrompt()
        
        Logger.debug("ResumeReviewService: ContentsFit prompt:\n\(prompt)")
        
        let requestID = UUID()
        currentRequestID = requestID
        
        Logger.debug("ResumeReviewService: About to send mixed request for ContentsFit check")
        LLMRequestService.shared.sendStructuredMixedRequest(
            promptText: prompt,
            base64Image: base64Image,
            responseType: ContentsFitResponse.self,
            jsonSchema: nil,  // Let LLMSchemaBuilder create the schema
            requestID: requestID
        ) { result in
            Logger.debug("ResumeReviewService: Received response for ContentsFit check")
            guard self.currentRequestID == requestID else { 
                Logger.debug("ResumeReviewService: Request ID mismatch, ignoring result")
                return 
            }
            
            switch result {
            case let .success(responseWrapper):
                
                do {
                    // Get detailed information about the response for debugging
                    Logger.debug("ContentsFit Response ID: \(responseWrapper.id)")
                    Logger.debug("ContentsFit Response Model: \(responseWrapper.model)")
                    
                    let content = responseWrapper.content
                    Logger.debug("ContentsFit Content from wrapper: \(content)")
                    
                    guard let responseData = content.data(using: .utf8) else {
                        throw NSError(domain: "ResumeReviewService", code: 1005, userInfo: [NSLocalizedDescriptionKey: "Failed to convert LLM content to Data for contentsFit."])
                    }
                    
                    // Log the JSON for debugging
                    Logger.debug("ContentsFit response JSON: \(content)")
                    
                    // First try the standard JSON decoder
                    do {
                        Logger.debug("ContentsFit: Attempting to decode response as JSON: \(responseData)")
                        let decodedResponse = try JSONDecoder().decode(ContentsFitResponse.self, from: responseData)
                        Logger.debug("ContentsFit: Successfully decoded with standard JSONDecoder. Result: contentsFit=\(decodedResponse.contentsFit)")
                        onComplete(.success(decodedResponse))
                    } catch let decodingError {
                        Logger.debug("Standard ContentsFit JSON decoding failed: \(decodingError.localizedDescription)")
                        
                        // Try string-based extraction first (fastest)
                        if content.contains("\"contentsFit\":true") || 
                           content.contains("\"contentsFit\": true") {
                            Logger.debug("Found contentsFit:true via string search")
                            // Try to extract overflow line count, default to 0
                            let overflowLineCount = self.extractOverflowLineCount(from: content) ?? 0
                            onComplete(.success(ContentsFitResponse(contentsFit: true, overflowLineCount: overflowLineCount)))
                            return
                        } else if content.contains("\"contentsFit\":false") || 
                                  content.contains("\"contentsFit\": false") {
                            Logger.debug("Found contentsFit:false via string search")
                            // Try to extract overflow line count, default to 0
                            let overflowLineCount = self.extractOverflowLineCount(from: content) ?? 0
                            onComplete(.success(ContentsFitResponse(contentsFit: false, overflowLineCount: overflowLineCount)))
                            return
                        }
                        
                        // Log the content for debugging
                        Logger.debug("ContentsFit: Raw content for manual inspection: \(content)")
                        
                        // If that fails, try JSONSerialization
                        do {
                            if let jsonObject = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                               let contentsFit = jsonObject["contentsFit"] as? Bool {
                                Logger.debug("Found contentsFit:\(contentsFit) via JSONSerialization")
                                let overflowLineCount = jsonObject["overflow_line_count"] as? Int ?? 0
                                onComplete(.success(ContentsFitResponse(contentsFit: contentsFit, overflowLineCount: overflowLineCount)))
                                return
                            }
                            
                            // One last attempt - look for true/false in nested JSON structures
                            // This handles cases where the value is deeply nested
                            let jsonString = String(data: responseData, encoding: .utf8) ?? ""
                            if jsonString.contains("true") && !jsonString.contains("false") {
                                // If only "true" appears, assume it's a contentsFit:true
                                Logger.debug("Assuming contentsFit:true based on JSON values")
                                onComplete(.success(ContentsFitResponse(contentsFit: true, overflowLineCount: 0)))
                                return
                            } else if jsonString.contains("false") && !jsonString.contains("true") {
                                // If only "false" appears, assume it's a contentsFit:false
                                Logger.debug("Assuming contentsFit:false based on JSON values")
                                onComplete(.success(ContentsFitResponse(contentsFit: false, overflowLineCount: 0)))
                                return
                            }
                            
                            // If all parsing fails, default to not fitting to force another iteration
                            Logger.debug("Could not parse contentsFit value, defaulting to false")
                            onComplete(.success(ContentsFitResponse(contentsFit: false, overflowLineCount: 0)))
                        } catch {
                            // All parsing failed, log details and default to false to continue
                            Logger.debug("All ContentsFit parsing failed: \(error.localizedDescription)")
                            Logger.debug("Raw JSON: \(content)")
                            Logger.debug("Defaulting to contentsFit:false to continue iterations")
                            onComplete(.success(ContentsFitResponse(contentsFit: false, overflowLineCount: 0)))
                        }
                    }
                } catch {
                    Logger.debug("Error in initial ContentsFitResponse handling: \(error.localizedDescription)")
                    // Default to false to force another attempt
                    onComplete(.success(ContentsFitResponse(contentsFit: false, overflowLineCount: 0)))
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
    
    /// Sends a request to reorder skills based on job relevance
    /// - Parameters:
    ///   - resume: The resume containing the skills
    ///   - appState: The application state for creating the LLM client
    ///   - onComplete: Completion callback with result
    @MainActor
    func sendReorderSkillsRequest(
        resume: Resume,
        appState: AppState,
        onComplete: @escaping (Result<ReorderSkillsResponseContainer, Error>) -> Void
    ) {
        guard let jobApp = resume.jobApp else {
            onComplete(.failure(NSError(domain: "ResumeReviewService", code: 1010, userInfo: [NSLocalizedDescriptionKey: "No job application associated with this resume."])))
            return
        }
        
        Logger.debug("ResumeReviewService: sendReorderSkillsRequest called (using new unified provider)")
        
        Task { @MainActor in
            do {
                let provider = ReorderSkillsProvider(
                    appState: appState,
                    resume: resume,
                    jobDescription: jobApp.jobDescription
                )
                
                let reorderedNodes = try await provider.fetchReorderedSkills()
                let responseContainer = ReorderSkillsResponseContainer(reorderedSkillsAndExpertise: reorderedNodes)
                onComplete(.success(responseContainer))
            } catch {
                Logger.error("ReorderSkillsProvider error: \(error.localizedDescription)")
                onComplete(.failure(error))
            }
        }
    }
    
    /// Cancels the current review request
    func cancelRequest() {
        currentRequestID = nil
        LLMRequestService.shared.cancelRequest()
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