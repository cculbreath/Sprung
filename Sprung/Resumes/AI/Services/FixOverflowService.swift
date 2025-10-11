// Sprung/Resumes/AI/Services/FixOverflowService.swift

import Foundation

struct FixOverflowStatus {
    let statusMessage: String
    let changeMessage: String
    let overflowLineCount: Int
}

@MainActor
class FixOverflowService {
    private let reviewService: ResumeReviewService
    private let exportCoordinator: ResumeExportCoordinator
    
    init(reviewService: ResumeReviewService, exportCoordinator: ResumeExportCoordinator) {
        self.reviewService = reviewService
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
            guard let skillsJsonString = reviewService.extractSkillsForFixOverflow(resume: resume) else {
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
            
            reviewService.sendFixFitsRequest(
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
            reviewService.sendContentsFitRequest(
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
