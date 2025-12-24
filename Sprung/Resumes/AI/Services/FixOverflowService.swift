// Sprung/Resumes/AI/Services/FixOverflowService.swift
import Foundation
struct FixOverflowStatus {
    let statusMessage: String
    let changeMessage: String
    let overflowLineCount: Int
}
@MainActor
class FixOverflowService {
    private let llm: LLMFacade
    private let query = ResumeReviewQuery()
    private let exportCoordinator: ResumeExportCoordinator
    private var currentRequestID: UUID?
    private var activeStreamingHandle: LLMStreamingHandle?

    init(llm: LLMFacade, exportCoordinator: ResumeExportCoordinator) {
        self.llm = llm
        self.exportCoordinator = exportCoordinator
    }
    func performFixOverflow(
        resume: Resume,
        allowEntityMerge: Bool,
        selectedModel: String,
        maxIterations: Int,
        supportsReasoning: Bool = false,
        onStatusUpdate: @escaping (FixOverflowStatus) -> Void,
        onReasoningUpdate: ((String) -> Void)? = nil
    ) async -> Result<String, Error> {
        var loopCount = 0
        var operationSuccess = false
        var currentOverflowLineCount = 0
        var statusMessage = ""
        var changeMessage = ""
        Logger.debug("FixOverflow: Starting performFixOverflow with max iterations: \(maxIterations)")
        // Ensure PDF is available
        do {
            try await ensurePDFAvailable(resume: resume, onStatusUpdate: onStatusUpdate)
        } catch {
            return .failure(error)
        }
        repeat {
            loopCount += 1
            Logger.debug("FixOverflow: Starting iteration \(loopCount) of \(maxIterations)")
            statusMessage = "Iteration \(loopCount)/\(maxIterations): Analyzing skills section..."
            onStatusUpdate(FixOverflowStatus(statusMessage: statusMessage, changeMessage: changeMessage, overflowLineCount: currentOverflowLineCount))
            // Convert PDF to image
            guard let currentPdfData = resume.pdfData,
                  let currentImageBase64 = ImageConversionService.shared.convertPDFToBase64Image(pdfData: currentPdfData)
            else {
                return .failure(FixOverflowError.pdfConversionFailed(iteration: loopCount))
            }
            Logger.debug("FixOverflow: Successfully converted PDF to image")
            // Extract skills
            guard let skillsJsonString = extractSkillsForFixOverflow(resume: resume) else {
                return .failure(FixOverflowError.skillsExtractionFailed(iteration: loopCount))
            }
            Logger.debug("FixOverflow: Successfully extracted skills JSON: \(skillsJsonString.prefix(100))...")
            if skillsJsonString == "[]" {
                statusMessage = "No 'Skills and Expertise' items found to optimize or section is empty."
                Logger.debug("FixOverflow: No skills items found to optimize")
                operationSuccess = true
                break
            }
            statusMessage = "Iteration \(loopCount): Asking AI to revise skills..."
            onStatusUpdate(FixOverflowStatus(statusMessage: statusMessage, changeMessage: changeMessage, overflowLineCount: currentOverflowLineCount))
            // Get AI suggestions
            let fixFitsResult = await getAISuggestions(
                skillsJsonString: skillsJsonString,
                currentImageBase64: currentImageBase64,
                currentOverflowLineCount: currentOverflowLineCount,
                selectedModel: selectedModel,
                allowEntityMerge: allowEntityMerge,
                iteration: loopCount,
                supportsReasoning: supportsReasoning,
                onReasoningUpdate: onReasoningUpdate
            )
            guard case let .success(fixFitsResponse) = fixFitsResult else {
                if case let .failure(error) = fixFitsResult {
                    return .failure(FixOverflowError.aiSuggestionsFailed(iteration: loopCount, error: error))
                } else {
                    return .failure(FixOverflowError.unknownAISuggestionsError(iteration: loopCount))
                }
            }
            // Apply changes
            statusMessage = "Iteration \(loopCount): Applying suggested revisions..."
            onStatusUpdate(FixOverflowStatus(statusMessage: statusMessage, changeMessage: changeMessage, overflowLineCount: currentOverflowLineCount))
            let (changesMade, newChangeMessage) = applyChanges(fixFitsResponse: fixFitsResponse, resume: resume, iteration: loopCount)
            changeMessage = newChangeMessage
            if !changesMade && loopCount > 1 {
                statusMessage = "AI suggested no further changes. Assuming content fits or cannot be further optimized."
                operationSuccess = true
                break
            }
            // Re-render PDF
            do {
                try await reRenderPDF(resume: resume, iteration: loopCount, onStatusUpdate: onStatusUpdate)
            } catch {
                return .failure(error)
            }
            // Check if content fits
            let contentsFitResult = await checkContentFits(resume: resume, selectedModel: selectedModel, iteration: loopCount)
            guard case let .success(contentsFitResponse) = contentsFitResult else {
                if case let .failure(error) = contentsFitResult {
                    return .failure(FixOverflowError.contentsFitCheckFailed(iteration: loopCount, error: error))
                } else {
                    return .failure(FixOverflowError.unknownContentsFitError(iteration: loopCount))
                }
            }
            Logger.debug("FixOverflow: contentsFitResponse.contentsFit = \(contentsFitResponse.contentsFit), overflowLineCount = \(contentsFitResponse.overflowLineCount)")
            currentOverflowLineCount = contentsFitResponse.overflowLineCount
            if contentsFitResponse.contentsFit {
                statusMessage = "AI confirms content fits after \(loopCount) iteration(s)."
                operationSuccess = true
                Logger.debug("FixOverflow: Content fits! Breaking loop.")
                break
            } else {
                let overflowDetail = currentOverflowLineCount > 0 ? " (\(currentOverflowLineCount) lines overflowing)" : ""
                Logger.debug("FixOverflow: Content does NOT fit\(overflowDetail). Will continue iterations if possible.")
            }
            if loopCount >= maxIterations {
                statusMessage = "Reached maximum iterations (\(maxIterations)). Manual review of skills section recommended."
                operationSuccess = false
                break
            }
            statusMessage = "Iteration \(loopCount): Content still overflowing. Preparing for next iteration..."
            onStatusUpdate(FixOverflowStatus(statusMessage: statusMessage, changeMessage: changeMessage, overflowLineCount: currentOverflowLineCount))
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        } while true
        let finalStatus = determineFinalStatus(
            operationSuccess: operationSuccess,
            loopCount: loopCount,
            maxIterations: maxIterations,
            statusMessage: statusMessage
        )
        exportCoordinator.debounceExport(resume: resume)
        return .success(finalStatus)
    }
    // MARK: - Networking Methods

    /// Sends a request to the LLM to revise skills for fitting
    /// - Parameters:
    ///   - skillsJsonString: JSON string representation of skills
    ///   - base64Image: Base64 encoded image of the resume
    ///   - overflowLineCount: Number of lines overflowing from previous contentsFit check
    ///   - allowEntityMerge: Whether to allow merging of redundant entries
    ///   - supportsReasoning: Whether the model supports reasoning (for streaming)
    ///   - onReasoningUpdate: Optional callback for reasoning content streaming
    ///   - onComplete: Completion callback with result
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
                Logger.debug("🔍 FixOverflowService: Sending fix fits request with model: \(modelId)")
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
                            throw NSError(domain: "FixOverflowService", code: 1005, userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 image data"])
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
                    Logger.debug("FixOverflowService: Fix fits request cancelled")
                    return
                }
                Logger.debug("✅ FixOverflowService: Fix fits request completed successfully")
                onComplete(.success(response))
            } catch {
                // Check if request was cancelled
                guard currentRequestID == requestID else {
                    Logger.debug("FixOverflowService: Fix fits request cancelled during error handling")
                    return
                }
                Logger.error("FixOverflowService: Fix fits request failed: \(error.localizedDescription)")
                onComplete(.failure(error))
            }
        }
    }

    /// Sends a request to the LLM to check if content fits
    /// - Parameters:
    ///   - base64Image: Base64 encoded image of the resume
    ///   - onComplete: Completion callback with result
    func sendContentsFitRequest(
        base64Image: String,
        modelId: String,
        onComplete: @escaping (Result<ContentsFitResponse, Error>) -> Void
    ) {
        let requestID = UUID()
        currentRequestID = requestID
        Task { @MainActor in
            do {
                Logger.debug("🔍 FixOverflowService: Sending contents fit request with model: \(modelId)")
                // Build the prompt using the centralized ResumeReviewQuery
                let prompt = query.buildContentsFitPrompt()
                Logger.debug("FixOverflowService: ContentsFit prompt:\n\(query.consoleFriendlyPrompt(prompt))")
                // Convert base64Image back to Data for LLMService
                guard let imageData = Data(base64Encoded: base64Image) else {
                    throw NSError(
                        domain: "FixOverflowService",
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
                    Logger.debug("FixOverflowService: Contents fit request cancelled")
                    return
                }
                Logger.debug("✅ FixOverflowService: Contents fit check completed successfully: contentsFit=\(response.contentsFit)")
                onComplete(.success(response))
            } catch {
                // Check if request was cancelled
                guard currentRequestID == requestID else {
                    Logger.debug("FixOverflowService: Contents fit request cancelled during error handling")
                    return
                }
                Logger.error("FixOverflowService: Contents fit request failed: \(error.localizedDescription)")
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

    // MARK: - Private Helper Methods
    private func ensurePDFAvailable(resume: Resume, onStatusUpdate: @escaping (FixOverflowStatus) -> Void) async throws {
        if resume.pdfData == nil {
            onStatusUpdate(FixOverflowStatus(statusMessage: "Generating initial PDF for analysis...", changeMessage: "", overflowLineCount: 0))
            Logger.debug("FixOverflow: No PDF data, generating...")
            try await exportCoordinator.ensureFreshRenderedText(for: resume)
            guard resume.pdfData != nil else {
                Logger.debug("FixOverflow: Failed to generate initial PDF")
                throw FixOverflowError.pdfGenerationFailed
            }
            Logger.debug("FixOverflow: Successfully generated initial PDF")
        } else {
            Logger.debug("FixOverflow: Using existing PDF data")
        }
    }
    private func getAISuggestions(
        skillsJsonString: String,
        currentImageBase64: String,
        currentOverflowLineCount: Int,
        selectedModel: String,
        allowEntityMerge: Bool,
        iteration: Int,
        supportsReasoning: Bool = false,
        onReasoningUpdate: ((String) -> Void)? = nil
    ) async -> Result<FixFitsResponseContainer, Error> {
        await withCheckedContinuation { continuation in
            // Only allow entity merge on the first iteration
            let allowMergeForThisIteration = allowEntityMerge && iteration == 1
            sendFixFitsRequest(
                skillsJsonString: skillsJsonString,
                base64Image: currentImageBase64,
                overflowLineCount: currentOverflowLineCount,
                modelId: selectedModel,
                allowEntityMerge: allowMergeForThisIteration,
                supportsReasoning: supportsReasoning,
                onReasoningUpdate: onReasoningUpdate
            ) { result in
                continuation.resume(returning: result)
            }
        }
    }
    private func applyChanges(fixFitsResponse: FixFitsResponseContainer, resume: Resume, iteration: Int) -> (changesMade: Bool, changeMessage: String) {
        var changesMadeInThisIteration = false
        var changedNodes: [(oldValue: String, newValue: String)] = []
        var changeMessage = ""
        // Handle merge operation
        if let mergeOp = fixFitsResponse.mergeOperation {
            Logger.debug("FixOverflow: Processing merge operation in iteration \(iteration)")
            if let keepNode = findTreeNode(byId: mergeOp.skillToKeepId, in: resume),
               let deleteNode = findTreeNode(byId: mergeOp.skillToDeleteId, in: resume) {
                let oldTitle = keepNode.name
                let oldDescription = keepNode.value
                keepNode.name = mergeOp.mergedTitle
                keepNode.value = mergeOp.mergedDescription
                // Delete the redundant node
                if let parent = deleteNode.parent,
                   let index = parent.children?.firstIndex(where: { $0.id == deleteNode.id }) {
                    parent.children?.remove(at: index)
                    // Update indices of remaining children
                    parent.children?.enumerated().forEach { index, child in
                        child.myIndex = index
                    }
                }
                changesMadeInThisIteration = true
                changedNodes.append((oldValue: "\(oldTitle): \(oldDescription) [merged with \(deleteNode.name)]",
                                   newValue: "\(mergeOp.mergedTitle): \(mergeOp.mergedDescription)"))
                changeMessage += "\n\nMerge performed: \(mergeOp.mergeReason)"
            }
        }
        // Handle regular revisions
        for revisedNode in fixFitsResponse.revisedSkillsAndExpertise {
            if let treeNode = findTreeNode(byId: revisedNode.id, in: resume) {
                var changed = false
                var oldDisplay = ""
                var newDisplay = ""
                if let newTitle = revisedNode.newTitle, treeNode.name != newTitle {
                    oldDisplay = "\(treeNode.name): \(treeNode.value)"
                    treeNode.name = newTitle
                    changed = true
                }
                if let newDescription = revisedNode.newDescription, treeNode.value != newDescription {
                    if oldDisplay.isEmpty {
                        oldDisplay = "\(treeNode.name): \(treeNode.value)"
                    }
                    treeNode.value = newDescription
                    changed = true
                }
                if changed {
                    newDisplay = "\(treeNode.name): \(treeNode.value)"
                    changesMadeInThisIteration = true
                    changedNodes.append((oldValue: oldDisplay, newValue: newDisplay))
                }
            } else {
                Logger.debug("Warning: TreeNode with ID \(revisedNode.id) not found for applying revision.")
            }
        }
        // Update change message with details
        if !changedNodes.isEmpty {
            var changesSummary = "Iteration \(iteration): \(changedNodes.count) node\(changedNodes.count > 1 ? "s" : "") updated:\n\n"
            for (index, change) in changedNodes.enumerated() {
                changesSummary += "\(index + 1). \"\(change.oldValue)\" → \"\(change.newValue)\"\n\n"
            }
            changeMessage = changesSummary + changeMessage
        }
        return (changesMadeInThisIteration, changeMessage)
    }
    private func reRenderPDF(resume: Resume, iteration: Int, onStatusUpdate: @escaping (FixOverflowStatus) -> Void) async throws {
        onStatusUpdate(FixOverflowStatus(statusMessage: "Re-rendering resume with changes...", changeMessage: "", overflowLineCount: 0))
        try await exportCoordinator.ensureFreshRenderedText(for: resume)
        guard resume.pdfData != nil else {
            throw FixOverflowError.pdfReRenderFailed(iteration: iteration)
        }
    }
    private func checkContentFits(resume: Resume, selectedModel: String, iteration: Int) async -> Result<ContentsFitResponse, Error> {
        guard let updatedPdfData = resume.pdfData,
              let updatedImageBase64 = ImageConversionService.shared.convertPDFToBase64Image(pdfData: updatedPdfData)
        else {
            return .failure(FixOverflowError.pdfConversionFailed(iteration: iteration))
        }
        Logger.debug("FixOverflow: About to send contentsFit request in iteration \(iteration)")
        return await withCheckedContinuation { continuation in
            Logger.debug("FixOverflow: Inside continuation for contentsFit request")
            sendContentsFitRequest(
                base64Image: updatedImageBase64,
                modelId: selectedModel
            ) { result in
                Logger.debug("FixOverflow: Received contentsFit response: \(result)")
                continuation.resume(returning: result)
            }
        }
    }
    private func findTreeNode(byId id: String, in resume: Resume) -> TreeNode? {
        return resume.nodes.first { $0.id == id }
    }
    private func determineFinalStatus(operationSuccess: Bool, loopCount: Int, maxIterations: Int, statusMessage: String) -> String {
        if operationSuccess {
            if !statusMessage.lowercased().contains("fits") {
                return "Skills section optimization complete."
            }
            return statusMessage
        } else if loopCount >= maxIterations {
            return statusMessage // Already set to max iterations message
        } else {
            return "Fix Overflow operation did not complete as expected. Please review."
        }
    }

    // MARK: - Private Streaming Methods
    /// Stream Grok Fix Fits request with reasoning support (text-only)
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
        // Parse the JSON response using shared parser
        let responseText = jsonResponse.isEmpty ? fullResponse : jsonResponse
        return try LLMResponseParser.parseJSON(responseText, as: T.self)
    }
}
// MARK: - Error Types
enum FixOverflowError: LocalizedError {
    case pdfGenerationFailed
    case pdfConversionFailed(iteration: Int)
    case skillsExtractionFailed(iteration: Int)
    case aiSuggestionsFailed(iteration: Int, error: Error)
    case unknownAISuggestionsError(iteration: Int)
    case pdfReRenderFailed(iteration: Int)
    case contentsFitCheckFailed(iteration: Int, error: Error)
    case unknownContentsFitError(iteration: Int)
    var errorDescription: String? {
        switch self {
        case .pdfGenerationFailed:
            return "Failed to generate initial PDF for Fix Overflow."
        case .pdfConversionFailed(let iteration):
            return "Error converting resume to image (Iteration \(iteration))."
        case .skillsExtractionFailed(let iteration):
            return "Error extracting skills from resume (Iteration \(iteration))."
        case .aiSuggestionsFailed(let iteration, let error):
            return "Error getting skill revisions (Iteration \(iteration)): \(error.localizedDescription)"
        case .unknownAISuggestionsError(let iteration):
            return "Unknown error getting skill revisions (Iteration \(iteration))."
        case .pdfReRenderFailed(let iteration):
            return "Failed to re-render PDF after applying changes (Iteration \(iteration))."
        case .contentsFitCheckFailed(let iteration, let error):
            return "Error checking content fit (Iteration \(iteration)): \(error.localizedDescription)"
        case .unknownContentsFitError(let iteration):
            return "Unknown error checking content fit (Iteration \(iteration))."
        }
    }
}
