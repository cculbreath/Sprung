//
//  ResumeReviseViewModel.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/4/25.
//

import Foundation
import SwiftUI
import SwiftData

/// ViewModel responsible for managing the complex resume revision workflow
/// Extracts business logic from AiCommsView to provide clean separation of concerns
@MainActor
@Observable
class ResumeReviseViewModel {
    
    // MARK: - Dependencies
    private let llmService: LLMService
    private let appState: AppState
    
    // MARK: - UI State (ViewModel Layer)
    var showResumeRevisionSheet: Bool = false
    var resumeRevisions: [ProposedRevisionNode] = []
    var feedbackNodes: [FeedbackNode] = []
    var currentRevisionNode: ProposedRevisionNode?
    var currentFeedbackNode: FeedbackNode?
    var aiResubmit: Bool = false
    
    // Review workflow navigation state (moved from ReviewView)
    var feedbackIndex: Int = 0
    var updateNodes: [[String: Any]] = []
    var isEditingResponse: Bool = false
    var isCommenting: Bool = false
    var isMoreCommenting: Bool = false
    
    // MARK: - Business Logic State
    private var currentConversationId: UUID?
    private(set) var isProcessingRevisions: Bool = false
    
    // AI Resubmission handling (from AiCommsView)
    private var isWaitingForResubmission: Bool = false
    
    // MARK: - Error Handling
    private(set) var lastError: String?
    private(set) var retryCount: Int = 0
    private let maxRetries: Int = 2
    
    // MARK: - Configuration
    private let revisionTimeout: TimeInterval = 180.0 // 3 minutes
    
    init(llmService: LLMService, appState: AppState) {
        self.llmService = llmService
        self.appState = appState
        
        // Watch for aiResubmit changes to trigger resubmission workflow
        // This replicates the onChange(of: aiResub) logic from AiCommsView
        setupAIResubmitWatcher()
    }
    
    /// Set up the aiResubmit watcher to trigger resubmission workflow
    /// This replicates the onChange(of: aiResub) functionality from AiCommsView
    private func setupAIResubmitWatcher() {
        // Note: In SwiftUI @Observable, we can observe changes via Combine or manual checking
        // For now, the aiResubmit change will be handled by calling processAIResubmissionWorkflow directly
        // when ReviewView sets aiResubmit = true
    }
    
    /// Handle aiResubmit workflow changes
    /// Called when RevisionReviewView sets aiResubmit = true
    /// The actual AI resubmission will be handled by UnifiedToolbar through existing workflows
    func handleAIResubmitChange() {
        guard aiResubmit else { return }
        
        Logger.debug("🔄 AI resubmit triggered - state updated for UI")
        
        // The aiResubmit = true state will trigger the resubmission workflow
        // through UnifiedToolbar's existing clarifying questions workflow
        // This maintains compatibility with the existing architecture
        
        isProcessingRevisions = true
    }
    
    // MARK: - Public Interface
    
    /// Start a new revision workflow and show the review UI
    /// - Parameters:
    ///   - resume: The resume to revise
    ///   - query: The revision query containing prompts and context
    ///   - modelId: The model to use for revisions
    func startRevisionWorkflowAndShowUI(
        resume: Resume,
        query: ResumeApiQuery,
        modelId: String
    ) async throws {
        
        // Reset UI state
        resumeRevisions = []
        feedbackNodes = []
        currentRevisionNode = nil
        currentFeedbackNode = nil
        aiResubmit = false
        isProcessingRevisions = true
        
        // Generate revisions using existing startRevisionWorkflow
        let revisions = try await startRevisionWorkflow(
            resume: resume,
            query: query,
            modelId: modelId
        )
        
        // Set up UI state for ReviewView
        resumeRevisions = revisions
        
        // Set up the first revision for review
        if !revisions.isEmpty {
            currentRevisionNode = revisions[0]
            currentFeedbackNode = FeedbackNode(
                id: revisions[0].id,
                originalValue: revisions[0].oldValue,
                proposedRevision: revisions[0].newValue,
                actionRequested: .unevaluated,
                reviewerComments: "",
                isTitleNode: revisions[0].isTitleNode
            )
        }
        
        isProcessingRevisions = false
        showResumeRevisionSheet = true
    }
    
    /// Original workflow method (kept for compatibility)
    func startRevisionWorkflow(
        resume: Resume,
        query: ResumeApiQuery,
        modelId: String
    ) async throws -> [ProposedRevisionNode] {
        
        // Start conversation with system prompt and user query
        let systemPrompt = query.genericSystemMessage.content
        let userPrompt = await query.wholeResumeQueryString()
        
        // Start conversation and get revisions
        let (conversationId, _) = try await llmService.startConversation(
            systemPrompt: systemPrompt,
            userMessage: userPrompt,
            modelId: modelId
        )
        
        self.currentConversationId = conversationId
        
        // Request structured revision output
        let revisions = try await llmService.continueConversationStructured(
            userMessage: "Please provide the revision suggestions in the specified JSON format.",
            modelId: modelId,
            conversationId: conversationId,
            responseType: RevisionsContainer.self
        )
        
        // Validate and process the revisions
        let validatedRevisions = validateRevisions(revisions.revArray, for: resume)
        
        return validatedRevisions
    }
    
    
    
    
    /// Generate clarifying questions for the resume revision
    /// - Parameters:
    ///   - resume: The resume to analyze
    ///   - query: The revision query
    ///   - modelId: The model to use for question generation
    /// - Returns: Clarifying questions request or nil if no questions needed
    func requestClarifyingQuestions(
        resume: Resume,
        query: ResumeApiQuery,
        modelId: String
    ) async throws -> ClarifyingQuestionsRequest? {
        
        Logger.debug("❓ Requesting clarifying questions")
        
        // Validate model capabilities
        try llmService.validateModel(modelId: modelId, for: [])
        
        // Create clarifying questions prompt using the generic system message
        let systemPrompt = query.genericSystemMessage.content
        let userContext = await query.wholeResumeQueryString()
        
        // Request clarifying questions
        let questionsRequest = try await llmService.executeStructured(
            prompt: "\(systemPrompt)\n\nResume Context:\n\(userContext)",
            modelId: modelId,
            responseType: ClarifyingQuestionsRequest.self
        )
        
        Logger.debug("📋 Generated \(questionsRequest.questions.count) clarifying questions")
        Logger.debug("🎯 Proceed with revisions: \(questionsRequest.proceedWithRevisions)")
        
        return questionsRequest
    }
    
    /// Apply only accepted changes to the resume tree structure
    /// Delegates to the FeedbackNode collection extension
    func applyAcceptedChanges(feedbackNodes: [FeedbackNode], to resume: Resume) {
        feedbackNodes.applyAcceptedChanges(to: resume)
    }
    
    // MARK: - Review Workflow Navigation (Moved from ReviewView)
    
    /// Save the current feedback and move to next node
    /// Clean interface that delegates to node logic
    func saveAndNext(response: PostReviewAction, resume: Resume) {
        guard let currentFeedbackNode = currentFeedbackNode else { return }
        
        // Let the feedback node handle its own action processing
        currentFeedbackNode.processAction(response)
        
        // Update UI state based on response
        switch response {
        case .acceptedWithChanges:
            isEditingResponse = false
        case .revise, .mandatedChangeNoComment:
            isCommenting = false
        default:
            break
        }
        
        nextNode(resume: resume)
    }
    
    /// Move to the next revision node in the workflow
    func nextNode(resume: Resume) {
        // Add current feedback node to array
        if let currentFeedbackNode = currentFeedbackNode {
            feedbackNodes.append(currentFeedbackNode)
            feedbackIndex += 1
            Logger.debug("Added node to feedbackNodes. New index: \(feedbackIndex)/\(resumeRevisions.count)")
        }

        if feedbackIndex < resumeRevisions.count {
            Logger.debug("Moving to next node at index \(feedbackIndex)")
            currentRevisionNode = resumeRevisions[feedbackIndex]
            currentFeedbackNode = currentRevisionNode?.createFeedbackNode()
        } else {
            Logger.debug("Reached end of revisionArray. Processing completion...")
            completeReviewWorkflow(with: resume)
        }
    }
    
    /// Complete the review workflow - apply changes and handle resubmission
    func completeReviewWorkflow(with resume: Resume) {
        // Log statistics and apply changes
        feedbackNodes.logFeedbackStatistics()
        feedbackNodes.applyAcceptedChanges(to: resume)
        
        // Check for resubmission
        let nodesToResubmit = feedbackNodes.nodesRequiringAIResubmission
        
        if !nodesToResubmit.isEmpty {
            Logger.debug("Resubmitting \(nodesToResubmit.count) nodes to AI...")
            // Keep only nodes that need AI intervention for the next round
            feedbackNodes = nodesToResubmit
            nodesToResubmit.logResubmissionSummary()
            
            // Start AI resubmission workflow
            startAIResubmission(with: resume)
        } else {
            Logger.debug("No nodes need resubmission. All changes applied, dismissing sheet...")
            showResumeRevisionSheet = false
        }
    }
    
    /// Start AI resubmission workflow
    private func startAIResubmission(with resume: Resume) {
        // Reset to original state before resubmitting to AI
        feedbackIndex = 0
        
        // Show loading UI
        aiResubmit = true
        
        // Ensure PDF is fresh before resubmission
        Task {
            do {
                Logger.debug("Starting PDF re-rendering for AI resubmission...")
                try await resume.ensureFreshRenderedText()
                Logger.debug("PDF rendering complete for AI resubmission")
                
                // The aiResubmit = true state will trigger the actual LLM call
                // through the existing workflow in UnifiedToolbar
                
            } catch {
                Logger.debug("Error rendering resume for AI resubmission: \(error)")
                await MainActor.run {
                    aiResubmit = false
                }
            }
        }
    }
    
    /// Initialize updateNodes for the review workflow
    func initializeUpdateNodes(for resume: Resume) {
        updateNodes = resume.getUpdatableNodes()
    }
    
    
    /// Clear conversation state and reset workflow
    func resetWorkflowState() {
        Logger.debug("🔄 Resetting revision workflow state")
        
        if let conversationId = currentConversationId {
            llmService.clearConversation(id: conversationId)
        }
        
        currentConversationId = nil
        retryCount = 0
        lastError = nil
        isProcessingRevisions = false
    }
    
    // MARK: - Private Helpers
    
    /// Validate revisions against current resume state
    func validateRevisions(_ revisions: [ProposedRevisionNode], for resume: Resume) -> [ProposedRevisionNode] {
        Logger.debug("🔍 Validating \(revisions.count) revisions")
        
        var validRevisions = revisions
        let updateNodes = resume.getUpdatableNodes()
        
        // Filter out revisions for nodes that no longer exist
        let currentNodeIds = Set(resume.nodes.map { $0.id })
        let initialCount = validRevisions.count
        validRevisions = validRevisions.filter { revNode in
            let exists = currentNodeIds.contains(revNode.id)
            if !exists {
                Logger.debug("⚠️ Filtering out revision for non-existent node: \(revNode.id)")
            }
            return exists
        }
        
        if validRevisions.count < initialCount {
            Logger.debug("🔍 Removed \(initialCount - validRevisions.count) revisions for non-existent nodes")
        }
        
        // Validate and fix revision node content
        for (index, item) in validRevisions.enumerated() {
            // Find matching node by ID
            let nodesWithSameId = updateNodes.filter { $0["id"] as? String == item.id }
            
            if !nodesWithSameId.isEmpty {
                var matchedNode: [String: Any]?
                
                // Handle multiple nodes with same ID (title vs value)
                if nodesWithSameId.count > 1 {
                    // Try to match by content first
                    if !item.oldValue.isEmpty {
                        matchedNode = nodesWithSameId.first { node in
                            let nodeValue = node["value"] as? String ?? ""
                            let nodeName = node["name"] as? String ?? ""
                            return nodeValue == item.oldValue || nodeName == item.oldValue
                        }
                    }
                    
                    // Fallback to title node preference
                    if matchedNode == nil {
                        matchedNode = nodesWithSameId.first { node in
                            node["isTitleNode"] as? Bool == true
                        } ?? nodesWithSameId.first
                    }
                } else {
                    matchedNode = nodesWithSameId.first
                }
                
                // Update revision with correct values
                if let matchedNode = matchedNode {
                    if validRevisions[index].oldValue.isEmpty {
                        let isTitleNode = matchedNode["isTitleNode"] as? Bool ?? false
                        if isTitleNode {
                            validRevisions[index].oldValue = matchedNode["name"] as? String ?? ""
                        } else {
                            validRevisions[index].oldValue = matchedNode["value"] as? String ?? ""
                        }
                        validRevisions[index].isTitleNode = isTitleNode
                    } else {
                        validRevisions[index].isTitleNode = matchedNode["isTitleNode"] as? Bool ?? false
                    }
                }
            }
            
            // Last resort: find by tree path
            else if !item.treePath.isEmpty {
                let treePath = item.treePath
                let components = treePath.components(separatedBy: " > ")
                if components.count > 1 {
                    let potentialMatches = updateNodes.filter { node in
                        let nodePath = node["tree_path"] as? String ?? ""
                        return nodePath == treePath || nodePath.hasSuffix(treePath)
                    }
                    
                    if let match = potentialMatches.first {
                        validRevisions[index].id = match["id"] as? String ?? item.id
                        let isTitleNode = match["isTitleNode"] as? Bool ?? false
                        if isTitleNode {
                            validRevisions[index].oldValue = match["name"] as? String ?? ""
                        } else {
                            validRevisions[index].oldValue = match["value"] as? String ?? ""
                        }
                        validRevisions[index].isTitleNode = isTitleNode
                    }
                }
            }
            
            // Final fallback: direct node lookup
            if validRevisions[index].oldValue.isEmpty && !validRevisions[index].id.isEmpty {
                if let treeNode = resume.nodes.first(where: { $0.id == validRevisions[index].id }) {
                    if validRevisions[index].isTitleNode {
                        validRevisions[index].oldValue = treeNode.name
                    } else {
                        validRevisions[index].oldValue = treeNode.value
                    }
                }
            }
        }
        
        Logger.debug("✅ Validated revisions: \(validRevisions.count) (from \(revisions.count))")
        return validRevisions
    }
    
    /// Filter feedback nodes to find those requiring AI resubmission
    private func filterNodesForAIResubmission(_ feedbackNodes: [FeedbackNode]) -> [FeedbackNode] {
        let aiActions: Set<PostReviewAction> = [
            .revise, .mandatedChange, .mandatedChangeNoComment, .rewriteNoComment
        ]
        
        let nodesToRevise = feedbackNodes.filter { aiActions.contains($0.actionRequested) }
        
        Logger.debug("🔍 Found \(nodesToRevise.count) nodes requiring AI resubmission")
        for node in nodesToRevise {
            Logger.debug("  - Node \(node.id): \(node.actionRequested.rawValue)")
        }
        
        return nodesToRevise
    }
    
    /// Create a revision prompt from feedback nodes
    private func createRevisionPrompt(feedbackNodes: [FeedbackNode]) -> String {
        var prompt = "Please revise the following items based on the feedback provided:\n\n"
        
        for (index, node) in feedbackNodes.enumerated() {
            prompt += "## Item \(index + 1)\n"
            prompt += "Original Text: \(node.originalValue)\n"
            prompt += "Previous Revision: \(node.proposedRevision)\n"
            prompt += "Action Requested: \(node.actionRequested.rawValue)\n"
            
            if !node.reviewerComments.isEmpty {
                prompt += "Reviewer Comments: \(node.reviewerComments)\n"
            }
            
            prompt += "\n"
        }
        
        prompt += "Please provide improved revisions that address the feedback, maintaining the same JSON format as before."
        
        return prompt
    }
    
    /// Format clarifying questions and answers for inclusion in prompt
    private func formatClarifyingQuestionsAndAnswers(_ qa: [QuestionAnswer]) -> String {
        var formatted = ""
        
        for item in qa {
            formatted += "Question ID: \(item.questionId)\n"
            if let answer = item.answer {
                formatted += "Answer: \(answer)\n\n"
            } else {
                formatted += "Answer: [No answer provided]\n\n"
            }
        }
        
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Supporting Types

enum RevisionProgress {
    case idle
    case generatingRevisions
    case awaitingUserReview
    case processingFeedback
    case completed
    case error(String)
    
    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .generatingRevisions:
            return "Generating revisions..."
        case .awaitingUserReview:
            return "Awaiting user review"
        case .processingFeedback:
            return "Processing feedback..."
        case .completed:
            return "Completed"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

enum RevisionError: LocalizedError {
    case noActiveConversation
    case maxRevisionsExceeded
    case invalidRevisionData
    case modelValidationFailed
    
    var errorDescription: String? {
        switch self {
        case .noActiveConversation:
            return "No active revision conversation found"
        case .maxRevisionsExceeded:
            return "Maximum number of revision rounds exceeded"
        case .invalidRevisionData:
            return "Invalid revision data received from AI"
        case .modelValidationFailed:
            return "Selected model does not support required capabilities"
        }
    }
}

// MARK: - Note: Using existing types from AITypes.swift and ResumeUpdateNode.swift
// - RevisionsContainer (with revArray property)
// - ClarifyingQuestionsRequest 
// - ClarifyingQuestion
// - QuestionAnswer