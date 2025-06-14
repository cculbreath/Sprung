// PhysCloudResume/Resumes/AI/Services/ReorderSkillsService.swift

import Foundation

struct ReorderSkillsStatus {
    let statusMessage: String
    let changeMessage: String
}

@MainActor
class ReorderSkillsService {
    private let reviewService: ResumeReviewService
    
    init(reviewService: ResumeReviewService) {
        self.reviewService = reviewService
    }
    
    func performReorderSkills(
        resume: Resume,
        selectedModel: String,
        appState: AppState,
        onStatusUpdate: @escaping (ReorderSkillsStatus) -> Void
    ) async -> Result<String, Error> {
        Logger.debug("ReorderSkills: Starting performReorderSkills")
        onStatusUpdate(ReorderSkillsStatus(statusMessage: "Analyzing skills section...", changeMessage: ""))
        
        // Validate job application exists
        if resume.jobApp == nil {
            return .failure(ReorderSkillsError.noJobApplication)
        }
        
        onStatusUpdate(ReorderSkillsStatus(statusMessage: "Asking AI to analyze and reorder skills for the target job position...", changeMessage: ""))
        
        // Send request to LLM to reorder skills
        let reorderResult = await getReorderSuggestions(resume: resume, selectedModel: selectedModel, appState: appState)
        
        guard case let .success(reorderResponse) = reorderResult else {
            if case let .failure(error) = reorderResult {
                return .failure(ReorderSkillsError.reorderingFailed(error: error))
            } else {
                return .failure(ReorderSkillsError.unknownReorderingError)
            }
        }
        
        // Apply the new ordering
        onStatusUpdate(ReorderSkillsStatus(statusMessage: "Applying new skill order...", changeMessage: ""))
        
        let (statusMessage, changeMessage) = generateOrderingMessages(resume: resume, reorderResponse: reorderResponse)
        
        // Apply the reordering to the actual tree nodes
        let success = reviewService.applySkillReordering(resume: resume, reorderedNodes: reorderResponse.reorderedSkillsAndExpertise)
        
        if success {
            // Re-render the resume with the new order
            onStatusUpdate(ReorderSkillsStatus(statusMessage: "Re-rendering resume with new skill order...", changeMessage: changeMessage))
            do {
                try await resume.ensureFreshRenderedText()
                onStatusUpdate(ReorderSkillsStatus(statusMessage: statusMessage, changeMessage: changeMessage))
                resume.debounceExport()
                return .success(statusMessage)
            } catch {
                return .failure(ReorderSkillsError.pdfReRenderFailed(error: error))
            }
        } else {
            return .failure(ReorderSkillsError.applyReorderingFailed)
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func getReorderSuggestions(resume: Resume, selectedModel: String, appState: AppState) async -> Result<ReorderSkillsResponseContainer, Error> {
        await withCheckedContinuation { continuation in
            reviewService.sendReorderSkillsRequest(
                resume: resume,
                appState: appState,
                modelId: selectedModel,
                onComplete: { result in
                    continuation.resume(returning: result)
                }
            )
        }
    }
    
    private func generateOrderingMessages(resume: Resume, reorderResponse: ReorderSkillsResponseContainer) -> (statusMessage: String, changeMessage: String) {
        // Collect current order of skills and their data
        var currentNodes: [(id: String, name: String, position: Int)] = []
        var skillsSectionNode: TreeNode?
        
        if let rootNode = resume.rootNode {
            skillsSectionNode = rootNode.children?.first(where: {
                $0.name.lowercased() == "skills-and-expertise" || $0.name.lowercased() == "skills and expertise"
            })
            
            if let skillsSection = skillsSectionNode, let children = skillsSection.children {
                // Get all top-level skills nodes in their current order
                for child in children.sorted(by: { $0.myIndex < $1.myIndex }) {
                    currentNodes.append((id: child.id, name: child.name, position: child.myIndex))
                    
                    // Also add subcategory children if they exist
                    if let subChildren = child.children?.sorted(by: { $0.myIndex < $1.myIndex }) {
                        for subChild in subChildren {
                            currentNodes.append((id: subChild.id, name: subChild.name, position: subChild.myIndex))
                        }
                    }
                }
            }
        }
        
        // Create a map of node IDs to their current positions for comparison
        var currentPositions: [String: Int] = [:]
        for node in currentNodes {
            currentPositions[node.id] = node.position
        }
        
        // Sort the nodes by their new position for display
        let sortedNodes = reorderResponse.reorderedSkillsAndExpertise.sorted { $0.newPosition < $1.newPosition }
        
        // Create a simple before/after ordering display
        var oldOrder = "Old Order:\n"
        var newOrder = "New Order:\n"
        
        // Sort current nodes by their position (old order)
        let sortedCurrentNodes = currentNodes.sorted { $0.position < $1.position }
        
        // Create old order listing
        for (index, node) in sortedCurrentNodes.enumerated() {
            oldOrder += "\(index+1): \(node.name)\n"
        }
        
        // Create new order listing
        for (index, node) in sortedNodes.enumerated() {
            newOrder += "\(index+1): \(node.originalValue)\n"
        }
        
        // Create status message with just the order summary
        let statusMessage = "Skills have been reordered for maximum relevance.\n\n\(oldOrder)\n\(newOrder)"
        
        // Create detailed change message that persists
        var changeMessage = "Skills reordered by position:\n\n"
        
        // Show position changes
        for node in sortedNodes {
            let nodeText = node.originalValue
            let oldPosition = currentPositions[node.id] ?? -1
            
            // Skip nodes that didn't move or we couldn't find positions for
            if oldPosition == -1 || oldPosition == node.newPosition {
                continue
            }
            
            let changeIndicator = oldPosition < node.newPosition ? "↓" : "↑"
            changeMessage += "• \(nodeText) moved from position \(oldPosition + 1) to \(node.newPosition + 1) \(changeIndicator)\n"
        }
        
        changeMessage += "\n\nReordered skills with reasons:\n\n"
        for node in sortedNodes {
            let nodeText = node.isTitleNode ? "**\(node.originalValue)**" : node.originalValue
            changeMessage += "- \(nodeText)\n  _\(node.reasonForReordering)_\n\n"
        }
        
        return (statusMessage, changeMessage)
    }
}

// MARK: - Error Types

enum ReorderSkillsError: LocalizedError {
    case noJobApplication
    case reorderingFailed(error: Error)
    case unknownReorderingError
    case applyReorderingFailed
    case pdfReRenderFailed(error: Error)
    
    var errorDescription: String? {
        switch self {
        case .noJobApplication:
            return "No job application associated with this resume. Add a job application first."
        case .reorderingFailed(let error):
            return "Error reordering skills: \(error.localizedDescription)"
        case .unknownReorderingError:
            return "Unknown error while reordering skills."
        case .applyReorderingFailed:
            return "Error applying new skill order to resume."
        case .pdfReRenderFailed(let error):
            return "Error re-rendering resume: \(error.localizedDescription)"
        }
    }
}