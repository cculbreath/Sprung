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
    /// Sends a request to the LLM to revise skills for fitting
    /// - Parameters:
    ///   - skillsJsonString: JSON string representation of skills
    ///   - base64Image: Base64 encoded image of the resume
    ///   - overflowLineCount: Number of lines overflowing from previous contentsFit check
    ///   - allowEntityMerge: Whether to allow merging of redundant entries
    ///   - supportsReasoning: Whether the model supports reasoning (for streaming)
    ///   - onReasoningUpdate: Optional callback for reasoning content streaming
    ///   - onComplete: Completion callback with result
    @MainActor
    func sendFixFitsRequest(
        skillsJsonString: String,
        base64Image: String,
        overflowLineCount: Int = 0,
        modelId: String,
        allowEntityMerge: Bool = false,
        supportsReasoning: Bool = false,
        onReasoningUpdate: ((String) -> Void)? = nil,
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
                // Check if we should use streaming for reasoning models
                let shouldStream = supportsReasoning && onReasoningUpdate != nil
                if shouldStream && provider == AIModels.Provider.grok {
                    Logger.debug("Using streaming approach for reasoning-capable Grok model: \(modelId)")
                    // Only Grok supports streaming since it's text-only
                    response = try await streamGrokFixFitsRequest(
                        skillsJsonString: skillsJsonString,
                        overflowLineCount: overflowLineCount,
                        allowEntityMerge: allowEntityMerge,
                        modelId: modelId,
                        onReasoningUpdate: onReasoningUpdate
                    )
                } else {
                    // Non-streaming approach for non-reasoning models or when streaming not requested
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
                        response = try await llm.executeStructured(
                            prompt: grokPrompt,
                            modelId: modelId,
                            as: FixFitsResponseContainer.self,
                            temperature: nil
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
                        response = try await llm.executeStructuredWithImages(
                            prompt: prompt,
                            modelId: modelId,
                            images: [imageData],
                            as: FixFitsResponseContainer.self,
                            temperature: nil
                        )
                    }
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
    ///   - base64Image: Base64 encoded image of the resume
    ///   - onComplete: Completion callback with result
    @MainActor
    func sendContentsFitRequest(
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
                Logger.debug("ResumeReviewService: ContentsFit prompt:\n\(query.consoleFriendlyPrompt(prompt))")
                // Convert base64Image back to Data for LLMService
                guard let imageData = Data(base64Encoded: base64Image) else {
                    throw NSError(
                        domain: "ResumeReviewService",
                        code: 1006,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 image data for contents fit check"]
                    )
                }
                // ContentsFit always uses images, so no streaming support
                // Multimodal structured request
                let response: ContentsFitResponse = try await llm.executeStructuredWithImages(
                    prompt: prompt,
                    modelId: modelId,
                    images: [imageData],
                    as: ContentsFitResponse.self
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
    /// Extracts skills for fix overflow operation with bundled title/description
    /// - Parameter resume: The resume to extract skills from
    /// - Returns: A JSON string representing the bundled skills
    func extractSkillsForFixOverflow(resume: Resume) -> String? {
        guard let rootNode = resume.rootNode else {
            Logger.debug("Error: Resume has no rootNode for skills extraction")
            return nil
        }
        // Find the skills section
        guard let skillsSection = rootNode.children?.first(where: {
            $0.name.lowercased() == "skills-and-expertise" || $0.name.lowercased() == "skills and expertise"
        }) else {
            Logger.debug("Error: 'Skills and Expertise' section not found")
            return nil
        }
        // Extract skills as a simple JSON structure
        return skillsSection.toJSONString()
    }
    /// Sends a request to reorder skills based on job relevance
    /// - Parameters:
    ///   - resume: The resume containing the skills
    ///   - modelId: The model to use for skill reordering
    ///   - onComplete: Completion callback with result
    @MainActor
    func sendReorderSkillsRequest(
        resume: Resume,
        modelId: String,
        onComplete: @escaping (Result<ReorderSkillsResponse, Error>) -> Void
    ) {
        guard let jobApp = resume.jobApp else {
            onComplete(.failure(NSError(
                domain: "ResumeReviewService",
                code: 1010,
                userInfo: [NSLocalizedDescriptionKey: "No job application associated with this resume."]
            )))
            return
        }
        Logger.debug("ResumeReviewService: sendReorderSkillsRequest called (using new SkillReorderService)")
        Task { @MainActor in
            do {
                let service = SkillReorderService(llmFacade: llm)
                let reorderedNodes = try await service.fetchReorderedSkills(
                    resume: resume,
                    jobDescription: jobApp.jobDescription,
                    modelId: modelId
                )
                let response = ReorderSkillsResponse(reorderedSkillsAndExpertise: reorderedNodes)
                onComplete(.success(response))
            } catch {
                Logger.error("SkillReorderService error: \(error.localizedDescription)")
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
    // MARK: - Helper Methods
    /// Apply skill reordering to the resume's tree structure
    @MainActor
    func applySkillReordering(resume: Resume, reorderedNodes: [ReorderedSkillNode]) -> Bool {
        guard let rootNode = resume.rootNode else {
            Logger.error("Cannot apply skill reordering: resume has no root node")
            return false
        }
        // Find the skills section
        guard let skillsSection = rootNode.children?.first(where: {
            $0.name.lowercased() == "skills-and-expertise" || $0.name.lowercased() == "skills and expertise"
        }) else {
            Logger.error("Cannot apply skill reordering: skills section not found")
            return false
        }
        // Get all skill nodes as a mutable array
        guard var skillNodes = skillsSection.children else {
            Logger.error("Cannot apply skill reordering: skills section has no children")
            return false
        }
        // Create a map of reordered positions
        var newPositions: [String: Int] = [:]
        for reorderedNode in reorderedNodes {
            newPositions[reorderedNode.id] = reorderedNode.newPosition
        }
        // Sort skill nodes according to new positions
        skillNodes.sort { node1, node2 in
            let pos1 = newPositions[node1.id] ?? Int.max
            let pos2 = newPositions[node2.id] ?? Int.max
            return pos1 < pos2
        }
        // Update each node's myIndex to reflect their new position
        for (index, node) in skillNodes.enumerated() {
            node.myIndex = index
        }
        // Update the skills section with reordered children
        skillsSection.children = skillNodes
        Logger.debug("✅ Successfully applied skill reordering: \(reorderedNodes.count) skills reordered")
        return true
    }
    // MARK: - Private Streaming Methods
    /// Stream Grok Fix Fits request with reasoning support (text-only)
    @MainActor
    private func streamGrokFixFitsRequest(
        skillsJsonString: String,
        overflowLineCount: Int,
        allowEntityMerge: Bool,
        modelId: String,
        onReasoningUpdate: ((String) -> Void)?
    ) async throws -> FixFitsResponseContainer {
        // Grok uses text-only approach
        let prompt = query.buildGrokFixFitsPrompt(
            skillsJsonString: skillsJsonString,
            overflowLineCount: overflowLineCount,
            allowEntityMerge: allowEntityMerge
        )
        // Configure reasoning parameters
        let reasoning = OpenRouterReasoning(
            effort: "high",
            includeReasoning: true
        )
        // Start streaming
        activeStreamingHandle?.cancel()
        let handle = try await llm.executeStructuredStreaming(
            prompt: prompt,
            modelId: modelId,
            as: FixFitsResponseContainer.self,
            reasoning: reasoning
        )
        activeStreamingHandle = handle
        defer { activeStreamingHandle = nil }
        return try await processStream(handle.stream, onReasoningUpdate: onReasoningUpdate)
    }
    /// Process streaming response and extract structured data
    @MainActor
    private func processStream<T: Codable>(
        _ stream: AsyncThrowingStream<LLMStreamChunkDTO, Error>,
        onReasoningUpdate: ((String) -> Void)?
    ) async throws -> T {
        var fullResponse = ""
        var collectingJSON = false
        var jsonResponse = ""
        for try await chunk in stream {
            // Handle reasoning content (supports both legacy and new reasoning_details format)
            if let reasoningContent = chunk.allReasoningText {
                onReasoningUpdate?(reasoningContent)
            }
            // Collect regular content
            if let content = chunk.content {
                fullResponse += content
                // Try to extract JSON from the response
                if content.contains("{") || collectingJSON {
                    collectingJSON = true
                    jsonResponse += content
                }
            }
        }
        // Parse the JSON response
        let responseText = jsonResponse.isEmpty ? fullResponse : jsonResponse
        return try parseJSONFromText(responseText, as: T.self)
    }
    /// Parse JSON from text content with fallback strategies
    @MainActor
    private func parseJSONFromText<T: Codable>(_ text: String, as type: T.Type) throws -> T {
        Logger.debug("🔍 Attempting to parse JSON from text: \(text.prefix(500))...")
        // First try direct parsing if the entire text is JSON
        if let jsonData = text.data(using: .utf8) {
            do {
                let result = try JSONDecoder().decode(type, from: jsonData)
                Logger.info("✅ Direct JSON parsing successful")
                return result
            } catch {
                Logger.debug("❌ Direct parsing failed: \(error)")
            }
        }
        // Try to extract JSON from markdown code blocks
        let patterns = [
            "```json\\s*([\\s\\S]*?)```",
            "```([\\s\\S]*?)```",
            "\\{[\\s\\S]*\\}"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                let extractedRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 0)
                if let swiftRange = Range(extractedRange, in: text) {
                    let extractedText = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let jsonData = extractedText.data(using: .utf8) {
                        do {
                            let result = try JSONDecoder().decode(type, from: jsonData)
                            Logger.info("✅ Extracted JSON parsing successful with pattern: \(pattern)")
                            return result
                        } catch {
                            Logger.debug("❌ Pattern \(pattern) extraction failed: \(error)")
                            continue
                        }
                    }
                }
            }
        }
        throw NSError(
            domain: "ResumeReviewService",
            code: 1007,
            userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON from response text"]
        )
    }
}
