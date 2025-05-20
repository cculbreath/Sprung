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
                schema: nil,
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
                    case .success(let response):
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
            schema: (name: schemaName, jsonString: schema),
            requestID: requestID
        ) { result in
            guard self.currentRequestID == requestID else { return }
            
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
        Logger.debug("ResumeReviewService: sendContentsFitRequest called")
        let prompt = PromptBuilderService.shared.buildContentsFitPrompt()
        let schemaName = "check_content_fit_schema"
        let schema = OverflowSchemas.contentsFitSchemaString
        
        Logger.debug("ResumeReviewService: ContentsFit prompt:\n\(prompt)")
        Logger.debug("ResumeReviewService: ContentsFit schema:\n\(schema)")
        
        let requestID = UUID()
        currentRequestID = requestID
        
        Logger.debug("ResumeReviewService: About to send mixed request for ContentsFit check")
        LLMRequestService.shared.sendMixedRequest(
            promptText: prompt,
            base64Image: base64Image,
            schema: (name: schemaName, jsonString: schema),
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
                            onComplete(.success(ContentsFitResponse(contentsFit: true)))
                            return
                        } else if content.contains("\"contentsFit\":false") || 
                                  content.contains("\"contentsFit\": false") {
                            Logger.debug("Found contentsFit:false via string search")
                            onComplete(.success(ContentsFitResponse(contentsFit: false)))
                            return
                        }
                        
                        // Log the content for debugging
                        Logger.debug("ContentsFit: Raw content for manual inspection: \(content)")
                        
                        // If that fails, try JSONSerialization
                        do {
                            if let jsonObject = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                               let contentsFit = jsonObject["contentsFit"] as? Bool {
                                Logger.debug("Found contentsFit:\(contentsFit) via JSONSerialization")
                                onComplete(.success(ContentsFitResponse(contentsFit: contentsFit)))
                                return
                            }
                            
                            // One last attempt - look for true/false in nested JSON structures
                            // This handles cases where the value is deeply nested
                            let jsonString = String(data: responseData, encoding: .utf8) ?? ""
                            if jsonString.contains("true") && !jsonString.contains("false") {
                                // If only "true" appears, assume it's a contentsFit:true
                                Logger.debug("Assuming contentsFit:true based on JSON values")
                                onComplete(.success(ContentsFitResponse(contentsFit: true)))
                                return
                            } else if jsonString.contains("false") && !jsonString.contains("true") {
                                // If only "false" appears, assume it's a contentsFit:false
                                Logger.debug("Assuming contentsFit:false based on JSON values")
                                onComplete(.success(ContentsFitResponse(contentsFit: false)))
                                return
                            }
                            
                            // If all parsing fails, default to not fitting to force another iteration
                            Logger.debug("Could not parse contentsFit value, defaulting to false")
                            onComplete(.success(ContentsFitResponse(contentsFit: false)))
                        } catch {
                            // All parsing failed, log details and default to false to continue
                            Logger.debug("All ContentsFit parsing failed: \(error.localizedDescription)")
                            Logger.debug("Raw JSON: \(content)")
                            Logger.debug("Defaulting to contentsFit:false to continue iterations")
                            onComplete(.success(ContentsFitResponse(contentsFit: false)))
                        }
                    }
                } catch {
                    Logger.debug("Error in initial ContentsFitResponse handling: \(error.localizedDescription)")
                    // Default to false to force another attempt
                    onComplete(.success(ContentsFitResponse(contentsFit: false)))
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
    ///   - onComplete: Completion callback with result
    @MainActor
    func sendReorderSkillsRequest(
        resume: Resume,
        onComplete: @escaping (Result<ReorderSkillsResponseContainer, Error>) -> Void
    ) {
        guard let jobApp = resume.jobApp else {
            onComplete(.failure(NSError(domain: "ResumeReviewService", code: 1010, userInfo: [NSLocalizedDescriptionKey: "No job application associated with this resume."])))
            return
        }
        
        Logger.debug("ResumeReviewService: sendReorderSkillsRequest called")
        
        // For reordering, get the simplified skills JSON with just names, IDs and order
        let simplifiedSkillsJson = TreeNodeExtractor.shared.extractSkillsForReordering(resume: resume) ?? "[]"
        
        let prompt = PromptBuilderService.shared.buildReorderSkillsPrompt(
            skillsJsonString: simplifiedSkillsJson,
            jobDescription: jobApp.jobDescription
        )
        let schemaName = "reorder_skills_schema"
        let schema = OverflowSchemas.reorderSkillsArraySchemaString
        
        Logger.debug("ResumeReviewService: ReorderSkills prompt:\n\(prompt)")
        Logger.debug("ResumeReviewService: ReorderSkills schema:\n\(schema)")
        
        let requestID = UUID()
        currentRequestID = requestID
        
        // Use sendMixedRequest instead of sendTextRequest to properly pass the schema validation
        LLMRequestService.shared.sendMixedRequest(
            promptText: prompt,
            base64Image: nil, // No image needed for this request
            schema: (name: schemaName, jsonString: schema),
            requestID: requestID
        ) { result in
            guard self.currentRequestID == requestID else { return }
            
            switch result {
            case let .success(responseWrapper):
                
                do {
                    Logger.debug("Response ID: \(responseWrapper.id)")
                    Logger.debug("Response Model: \(responseWrapper.model)")
                    
                    let content = responseWrapper.content
                    Logger.debug("Content from wrapper: \(content.prefix(100))...")
                    
                    guard let responseData = content.data(using: .utf8) else {
                        throw NSError(domain: "ResumeReviewService", code: 1004, userInfo: [NSLocalizedDescriptionKey: "Failed to convert LLM content to Data."])
                    }
                    
                    // Log the JSON for debugging
                    Logger.debug("ReorderSkills response JSON: \(content)")
                    
                    // First try the standard JSON decoder
                    do {
                        let decodedResponse = try JSONDecoder().decode(ReorderSkillsResponseContainer.self, from: responseData)
                        onComplete(.success(decodedResponse))
                    } catch let decodingError {
                        Logger.debug("Standard JSON decoding failed: \(decodingError.localizedDescription)")
                        
                        // If standard decoding fails, try a more lenient approach using JSONSerialization
                        do {
                            // Try parsing as a direct array (as seen in the logs)
                            if let jsonArray = try? JSONSerialization.jsonObject(with: responseData) as? [[String: Any]] {
                                // We have a direct array structure
                                Logger.debug("Detected direct array response format")
                                
                                // Convert to our model manually
                                var reorderedNodes: [ReorderedSkillNode] = []
                                
                                for item in jsonArray {
                                    if let id = item["id"] as? String,
                                       let originalValue = item["originalValue"] as? String,
                                       let treePath = item["treePath"] as? String,
                                       let isTitleNode = item["isTitleNode"] as? Bool {
                                        
                                        // Handle different position field names
                                        let newPosition: Int
                                        if let pos = item["newPosition"] as? Int {
                                            newPosition = pos
                                        } else if let pos = item["recommendedPosition"] as? Int {
                                            newPosition = pos
                                        } else {
                                            Logger.debug("Warning: Missing position data for node \(id)")
                                            continue
                                        }
                                        
                                        // Handle different reason field names
                                        let reason: String
                                        if let r = item["reasonForReordering"] as? String {
                                            reason = r
                                        } else if let r = item["reason"] as? String {
                                            reason = r
                                        } else {
                                            reason = "No reason provided"
                                        }
                                        
                                        let node = ReorderedSkillNode(
                                            id: id,
                                            originalValue: originalValue,
                                            newPosition: newPosition,
                                            reasonForReordering: reason,
                                            isTitleNode: isTitleNode,
                                            treePath: treePath
                                        )
                                        reorderedNodes.append(node)
                                    }
                                }
                                
                                if !reorderedNodes.isEmpty {
                                    // If we parsed something, return it
                                    Logger.debug("Successfully parsed \(reorderedNodes.count) nodes from direct array")
                                    onComplete(.success(ReorderSkillsResponseContainer(reorderedSkillsAndExpertise: reorderedNodes)))
                                    return
                                }
                            }
                            
                            // Try the original container format too
                            if let jsonObject = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                               let skillsArray = jsonObject["reordered_skills_and_expertise"] as? [[String: Any]] {
                                
                                Logger.debug("Detected container with reordered_skills_and_expertise")
                                
                                // Convert to our model manually
                                var reorderedNodes: [ReorderedSkillNode] = []
                                
                                for item in skillsArray {
                                    if let id = item["id"] as? String,
                                       let originalValue = item["originalValue"] as? String,
                                       let treePath = item["treePath"] as? String,
                                       let isTitleNode = item["isTitleNode"] as? Bool {
                                        
                                        // Handle different position field names
                                        let newPosition: Int
                                        if let pos = item["newPosition"] as? Int {
                                            newPosition = pos
                                        } else if let pos = item["recommendedPosition"] as? Int {
                                            newPosition = pos
                                        } else {
                                            Logger.debug("Warning: Missing position data for node \(id)")
                                            continue
                                        }
                                        
                                        // Handle different reason field names
                                        let reason: String
                                        if let r = item["reasonForReordering"] as? String {
                                            reason = r
                                        } else if let r = item["reason"] as? String {
                                            reason = r
                                        } else {
                                            reason = "No reason provided"
                                        }
                                        
                                        let node = ReorderedSkillNode(
                                            id: id,
                                            originalValue: originalValue,
                                            newPosition: newPosition,
                                            reasonForReordering: reason,
                                            isTitleNode: isTitleNode,
                                            treePath: treePath
                                        )
                                        reorderedNodes.append(node)
                                    }
                                }
                                
                                if !reorderedNodes.isEmpty {
                                    // If we parsed something, return it
                                    Logger.debug("Successfully parsed \(reorderedNodes.count) nodes from container")
                                    onComplete(.success(ReorderSkillsResponseContainer(reorderedSkillsAndExpertise: reorderedNodes)))
                                    return
                                }
                            }
                            
                            // Couldn't handle it with manual parsing either
                            throw decodingError
                        } catch {
                            // All parsing failed, log full error details
                            Logger.debug("Error decoding ReorderSkillsResponseContainer: \(error.localizedDescription)")
                            Logger.debug("Raw JSON: \(content)")
                            onComplete(.failure(error))
                        }
                    }
                } catch {
                    Logger.debug("Error decoding ReorderSkillsResponseContainer: \(error.localizedDescription)")
                    onComplete(.failure(error))
                }
                
            case let .failure(error):
                onComplete(.failure(error))
            }
        }
    }
    
    /// Cancels the current review request
    func cancelRequest() {
        currentRequestID = nil
        LLMRequestService.shared.cancelRequest()
    }
}