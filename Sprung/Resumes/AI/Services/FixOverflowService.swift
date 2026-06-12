// Sprung/Resumes/AI/Services/FixOverflowService.swift
import Foundation
struct FixOverflowStatus {
    let statusMessage: String
    let changeMessage: String
    let pageCount: Int
    let pageLimit: Int
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
        writersVoice: String,
        supportsReasoning: Bool = false,
        onStatusUpdate: @escaping (FixOverflowStatus) -> Void,
        onReasoningUpdate: ((String) -> Void)? = nil
    ) async -> Result<String, Error> {
        var loopCount = 0
        var operationSuccess = false
        var statusMessage = ""
        var changeMessage = ""
        Logger.debug("FixOverflow: Starting performFixOverflow with max iterations: \(maxIterations)")

        // Resolve the deterministic page target from the template manifest.
        guard let template = resume.template else {
            return .failure(FixOverflowError.noTemplate)
        }
        let manifest = TemplateManifestDefaults.manifest(for: template)
        // Fix Overflow's contract is fitting the declared page budget. Templates
        // that declare no pageLimit are single-page by this feature's definition;
        // the target is surfaced in every status update so this is never silent.
        let pageLimit = manifest.pageLimit ?? 1
        var pageCount = 0

        func status(_ message: String) {
            onStatusUpdate(FixOverflowStatus(
                statusMessage: message,
                changeMessage: changeMessage,
                pageCount: pageCount,
                pageLimit: pageLimit
            ))
        }

        // Always evaluate against a fresh render of the current tree state.
        do {
            status("Rendering resume for analysis (page limit: \(pageLimit))...")
            pageCount = try await renderAndCountPages(resume: resume, iteration: loopCount)
        } catch {
            return .failure(error)
        }
        if pageCount <= pageLimit {
            return .success("Content already fits: \(pageCount) page\(pageCount == 1 ? "" : "s") within the \(pageLimit)-page limit. No changes needed.")
        }

        // Only nodes the user marked editable may be rewritten or merged.
        let editableNodeIds: Set<String>
        do {
            editableNodeIds = try editableSkillNodeIds(resume: resume)
        } catch {
            return .failure(error)
        }

        repeat {
            loopCount += 1
            Logger.debug("FixOverflow: Starting iteration \(loopCount) of \(maxIterations)")
            status("Iteration \(loopCount)/\(maxIterations): Analyzing skills section...")
            // Convert all PDF pages to images so the model sees the overflow
            guard let currentPdfData = resume.pdfData,
                  let pageImages = ImageConversionService.shared.convertPDFToAllPageImages(pdfData: currentPdfData),
                  !pageImages.isEmpty
            else {
                return .failure(FixOverflowError.pdfConversionFailed(iteration: loopCount))
            }
            Logger.debug("FixOverflow: Converted PDF to \(pageImages.count) page image(s)")
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
            status("Iteration \(loopCount): Asking AI to revise skills...")
            // Get AI suggestions
            let fixFitsResult = await getAISuggestions(
                skillsJsonString: skillsJsonString,
                pageImages: pageImages,
                pageCount: pageCount,
                pageLimit: pageLimit,
                editableNodeIds: editableNodeIds,
                writersVoice: writersVoice,
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
            // Apply changes (editable nodes only)
            status("Iteration \(loopCount): Applying suggested revisions...")
            let (changesMade, newChangeMessage) = applyChanges(
                fixFitsResponse: fixFitsResponse,
                resume: resume,
                editableNodeIds: editableNodeIds,
                iteration: loopCount
            )
            changeMessage = newChangeMessage
            if !changesMade {
                statusMessage = "AI suggested no further changes. Content cannot be optimized further within the editable nodes."
                operationSuccess = false
                break
            }
            // Re-render and deterministically check the page count
            do {
                status("Re-rendering resume with changes...")
                pageCount = try await renderAndCountPages(resume: resume, iteration: loopCount)
            } catch {
                return .failure(error)
            }
            Logger.debug("FixOverflow: Deterministic page count = \(pageCount), limit = \(pageLimit)")
            if pageCount <= pageLimit {
                statusMessage = "Content fits within \(pageLimit) page\(pageLimit == 1 ? "" : "s") after \(loopCount) iteration(s)."
                operationSuccess = true
                Logger.debug("FixOverflow: Content fits! Breaking loop.")
                break
            }
            Logger.debug("FixOverflow: Content spans \(pageCount) pages (limit \(pageLimit)). Will continue iterations if possible.")
            if loopCount >= maxIterations {
                statusMessage = "Reached maximum iterations (\(maxIterations)); resume still spans \(pageCount) pages (limit \(pageLimit)). Manual review of skills section recommended."
                operationSuccess = false
                break
            }
            status("Iteration \(loopCount): Still \(pageCount) pages (limit \(pageLimit)). Preparing for next iteration...")
        } while true
        let finalStatus = determineFinalStatus(
            operationSuccess: operationSuccess,
            statusMessage: statusMessage
        )
        exportCoordinator.debounceExport(resume: resume)
        return .success(finalStatus)
    }
    // MARK: - Networking Methods

    /// Sends a request to the LLM to revise skills for fitting
    /// - Parameters:
    ///   - skillsJsonString: JSON string representation of skills
    ///   - pageImages: Rendered PDF page images of the current resume
    ///   - pageCount: Current rendered page count
    ///   - pageLimit: Page budget from the template manifest
    ///   - editableNodeIds: IDs of nodes the model is allowed to modify
    ///   - writersVoice: Canonical voice block (empty when unavailable)
    ///   - allowEntityMerge: Whether to allow merging of redundant entries
    ///   - supportsReasoning: Whether the model supports reasoning (for streaming)
    ///   - onReasoningUpdate: Optional callback for reasoning content streaming
    ///   - onComplete: Completion callback with result
    func sendFixFitsRequest(
        skillsJsonString: String,
        pageImages: [Data],
        pageCount: Int,
        pageLimit: Int,
        modelId: String,
        editableNodeIds: Set<String>,
        writersVoice: String,
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
                Logger.debug("🔍 Using allowEntityMerge: \(allowEntityMerge), pages: \(pageCount)/\(pageLimit)")
                let response: FixFitsResponseContainer
                // Check if we should use streaming for reasoning models
                let shouldStream = supportsReasoning && onReasoningUpdate != nil
                if shouldStream && provider == AIModels.Provider.grok {
                    Logger.debug("Using streaming approach for reasoning-capable Grok model: \(modelId)")
                    // Only Grok supports streaming since it's text-only
                    response = try await streamGrokFixFitsRequest(
                        skillsJsonString: skillsJsonString,
                        pageCount: pageCount,
                        pageLimit: pageLimit,
                        editableNodeIds: editableNodeIds,
                        writersVoice: writersVoice,
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
                            pageCount: pageCount,
                            pageLimit: pageLimit,
                            editableNodeIds: editableNodeIds,
                            writersVoice: writersVoice,
                            allowEntityMerge: allowEntityMerge
                        )
                        // Text-only structured request for Grok
                        response = try await llm.executeStructured(
                            prompt: grokPrompt,
                            modelId: modelId,
                            as: FixFitsResponseContainer.self
                        )
                    } else {
                        Logger.debug("Using standard image-based approach for fix fits request")
                        // Standard approach for other models (OpenAI, Claude, Gemini)
                        let prompt = query.buildFixFitsPrompt(
                            skillsJsonString: skillsJsonString,
                            pageCount: pageCount,
                            pageLimit: pageLimit,
                            editableNodeIds: editableNodeIds,
                            writersVoice: writersVoice,
                            allowEntityMerge: allowEntityMerge
                        )
                        // Multimodal structured request with all rendered pages
                        response = try await llm.executeStructuredWithImages(
                            prompt: prompt,
                            modelId: modelId,
                            images: pageImages,
                            as: FixFitsResponseContainer.self
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

    /// Extracts skills for fix overflow operation with bundled title/description
    /// - Parameter resume: The resume to extract skills from
    /// - Returns: A JSON string representing the bundled skills
    func extractSkillsForFixOverflow(resume: Resume) -> String? {
        guard let skillsSection = Self.skillsSection(in: resume) else {
            Logger.debug("Error: 'Skills and Expertise' section not found")
            return nil
        }
        // Extract skills as a simple JSON structure
        return skillsSection.toJSONString()
    }

    /// Locates the 'Skills and Expertise' section node in a resume tree.
    static func skillsSection(in resume: Resume) -> TreeNode? {
        guard let rootNode = resume.rootNode else { return nil }
        return rootNode.children?.first(where: {
            $0.name.lowercased() == "skills-and-expertise" || $0.name.lowercased() == "skills and expertise"
        })
    }

    /// A node may be mutated only when it is part of the user's editable
    /// selection: directly marked `.aiToReplace`, or inheriting from an
    /// editable ancestor without an `.excludedFromGroup` opt-out.
    static func isEffectivelyEditable(_ node: TreeNode) -> Bool {
        if node.status == .aiToReplace { return true }
        if node.status == .excludedFromGroup { return false }
        return node.isInheritedAISelection
    }

    // MARK: - Private Helper Methods
    private func editableSkillNodeIds(resume: Resume) throws -> Set<String> {
        guard let skillsSection = Self.skillsSection(in: resume) else {
            throw FixOverflowError.skillsExtractionFailed(iteration: 0)
        }
        var ids: Set<String> = []
        func collect(_ node: TreeNode) {
            if Self.isEffectivelyEditable(node) {
                ids.insert(node.id)
            }
            for child in node.children ?? [] {
                collect(child)
            }
        }
        for child in skillsSection.children ?? [] {
            collect(child)
        }
        guard !ids.isEmpty else {
            throw FixOverflowError.noEditableSkillNodes
        }
        return ids
    }
    /// Re-render the resume (bypassing the freshness short-circuit) and return
    /// the deterministic page count of the resulting PDF.
    private func renderAndCountPages(resume: Resume, iteration: Int) async throws -> Int {
        try await exportCoordinator.forceRender(for: resume)
        guard let pdfData = resume.pdfData else {
            throw FixOverflowError.pdfReRenderFailed(iteration: iteration)
        }
        let pageCount = RevisionPDFRenderer.countPDFPages(pdfData)
        guard pageCount > 0 else {
            throw FixOverflowError.pageCountFailed(iteration: iteration)
        }
        return pageCount
    }
    private func getAISuggestions(
        skillsJsonString: String,
        pageImages: [Data],
        pageCount: Int,
        pageLimit: Int,
        editableNodeIds: Set<String>,
        writersVoice: String,
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
                pageImages: pageImages,
                pageCount: pageCount,
                pageLimit: pageLimit,
                modelId: selectedModel,
                editableNodeIds: editableNodeIds,
                writersVoice: writersVoice,
                allowEntityMerge: allowMergeForThisIteration,
                supportsReasoning: supportsReasoning,
                onReasoningUpdate: onReasoningUpdate
            ) { result in
                continuation.resume(returning: result)
            }
        }
    }
    private func applyChanges(
        fixFitsResponse: FixFitsResponseContainer,
        resume: Resume,
        editableNodeIds: Set<String>,
        iteration: Int
    ) -> (changesMade: Bool, changeMessage: String) {
        var changesMadeInThisIteration = false
        var changedNodes: [(oldValue: String, newValue: String)] = []
        var changeMessage = ""
        // Handle merge operation
        if let mergeOp = fixFitsResponse.mergeOperation {
            Logger.debug("FixOverflow: Processing merge operation in iteration \(iteration)")
            if !editableNodeIds.contains(mergeOp.skillToKeepId) || !editableNodeIds.contains(mergeOp.skillToDeleteId) {
                Logger.warning("FixOverflow: Merge proposal rejected — node(s) not marked editable (keep: \(mergeOp.skillToKeepId), delete: \(mergeOp.skillToDeleteId))")
            } else if let keepNode = findTreeNode(byId: mergeOp.skillToKeepId, in: resume),
                      let deleteNode = findTreeNode(byId: mergeOp.skillToDeleteId, in: resume) {
                let oldTitle = keepNode.name
                let oldDescription = keepNode.value
                keepNode.name = mergeOp.mergedTitle
                keepNode.value = mergeOp.mergedDescription
                // Detach the redundant node (restorable until the user accepts)
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
            guard editableNodeIds.contains(revisedNode.id) else {
                Logger.warning("FixOverflow: Skipping revision for node \(revisedNode.id) — not marked editable")
                continue
            }
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
    private func findTreeNode(byId id: String, in resume: Resume) -> TreeNode? {
        return resume.nodes.first { $0.id == id }
    }
    private func determineFinalStatus(operationSuccess: Bool, statusMessage: String) -> String {
        if operationSuccess {
            if !statusMessage.lowercased().contains("fits") {
                return "Skills section optimization complete."
            }
            return statusMessage
        } else if !statusMessage.isEmpty {
            return statusMessage
        } else {
            return "Fix Overflow operation did not complete as expected. Please review."
        }
    }

    // MARK: - Private Streaming Methods
    /// Stream Grok Fix Fits request with reasoning support (text-only)
    private func streamGrokFixFitsRequest(
        skillsJsonString: String,
        pageCount: Int,
        pageLimit: Int,
        editableNodeIds: Set<String>,
        writersVoice: String,
        allowEntityMerge: Bool,
        modelId: String,
        onReasoningUpdate: ((String) -> Void)?
    ) async throws -> FixFitsResponseContainer {
        // Grok uses text-only approach
        let prompt = query.buildGrokFixFitsPrompt(
            skillsJsonString: skillsJsonString,
            pageCount: pageCount,
            pageLimit: pageLimit,
            editableNodeIds: editableNodeIds,
            writersVoice: writersVoice,
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
        return try JSONResponseParser.parseText(responseText, as: T.self)
    }
}
// MARK: - Error Types
enum FixOverflowError: LocalizedError {
    case noTemplate
    case noEditableSkillNodes
    case pdfConversionFailed(iteration: Int)
    case skillsExtractionFailed(iteration: Int)
    case aiSuggestionsFailed(iteration: Int, error: Error)
    case unknownAISuggestionsError(iteration: Int)
    case pdfReRenderFailed(iteration: Int)
    case pageCountFailed(iteration: Int)
    var errorDescription: String? {
        switch self {
        case .noTemplate:
            return "This resume has no template assigned. Assign a template before running Fix Overflow."
        case .noEditableSkillNodes:
            return "No 'Skills and Expertise' entries are marked editable. Mark the entries you want the AI to revise (AI status) and try again."
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
        case .pageCountFailed(let iteration):
            return "Could not determine the page count of the rendered PDF (Iteration \(iteration))."
        }
    }
}
