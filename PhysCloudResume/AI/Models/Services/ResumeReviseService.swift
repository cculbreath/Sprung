//
//  ResumeReviseService.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/4/25.
//

import Foundation
import SwiftUI
import SwiftData

/// Service responsible for managing the complex resume revision workflow
/// Extracts business logic from AiCommsView to provide clean separation of concerns
@MainActor
@Observable
class ResumeReviseService {
    
    // MARK: - Dependencies
    private let llmService: LLMService
    private let appState: AppState
    
    // MARK: - State Management
    private var currentConversationId: UUID?
    private var revisionRounds: Int = 0
    private let maxRevisionRounds: Int = 5
    
    // MARK: - Revision Tracking
    private(set) var currentRevisions: [ProposedRevisionNode] = []
    private(set) var pendingFeedback: [FeedbackNode] = []
    private(set) var isProcessingRevisions: Bool = false
    private(set) var revisionProgress: RevisionProgress = .idle
    
    // MARK: - Error Handling
    private(set) var lastError: String?
    private(set) var retryCount: Int = 0
    private let maxRetries: Int = 2
    
    // MARK: - Configuration
    private let revisionTimeout: TimeInterval = 180.0 // 3 minutes
    
    init(llmService: LLMService, appState: AppState) {
        self.llmService = llmService
        self.appState = appState
    }
    
    // MARK: - Public Interface
    
    /// Start a new revision workflow for a resume
    /// - Parameters:
    ///   - resume: The resume to revise
    ///   - query: The revision query containing prompts and context
    ///   - modelId: The model to use for revisions
    ///   - clarifyingQuestions: Optional clarifying questions and answers
    /// - Returns: Array of proposed revision nodes
    func startRevisionWorkflow(
        resume: Resume,
        query: ResumeApiQuery,
        modelId: String,
        clarifyingQuestions: [QuestionAnswer]? = nil
    ) async throws -> [ProposedRevisionNode] {
        
        Logger.debug("🔄 Starting revision workflow for resume: \(resume.id)")
        
        // Reset state for new workflow
        resetWorkflowState()
        revisionProgress = .generatingRevisions
        
        // Validate model capabilities
        try llmService.validateModel(modelId: modelId, for: [])
        
        // Start conversation with system prompt and user query
        let systemPrompt = query.genericSystemMessage.content
        let userPrompt = await query.wholeResumeQueryString()
        
        Logger.debug("📝 System prompt length: \(systemPrompt.count) chars")
        Logger.debug("📝 User prompt length: \(userPrompt.count) chars")
        
        // Include clarifying questions in conversation if provided
        var conversationPrompt = userPrompt
        if let questions = clarifyingQuestions, !questions.isEmpty {
            let qaSection = formatClarifyingQuestionsAndAnswers(questions)
            conversationPrompt += "\n\n## Clarifying Questions & Answers\n\(qaSection)"
            Logger.debug("📋 Added \(questions.count) clarifying questions to prompt")
        }
        
        // Start conversation and get revisions
        let (conversationId, _) = try await llmService.startConversation(
            systemPrompt: systemPrompt,
            userMessage: conversationPrompt,
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
        self.currentRevisions = validatedRevisions
        self.revisionRounds = 1
        
        revisionProgress = .awaitingUserReview
        Logger.debug("✅ Generated \(validatedRevisions.count) validated revisions")
        
        return validatedRevisions
    }
    
    /// Process user feedback and generate new revisions for rejected items
    /// - Parameters:
    ///   - feedbackNodes: Array of feedback from user review
    ///   - resume: The current resume state
    ///   - modelId: The model to use for re-revision
    /// - Returns: New revision nodes for items that need AI attention
    func processFeedbackAndRevise(
        feedbackNodes: [FeedbackNode],
        resume: Resume,
        modelId: String
    ) async throws -> [ProposedRevisionNode] {
        
        guard let conversationId = currentConversationId else {
            throw RevisionError.noActiveConversation
        }
        
        guard revisionRounds < maxRevisionRounds else {
            throw RevisionError.maxRevisionsExceeded
        }
        
        Logger.debug("🔄 Processing \(feedbackNodes.count) feedback nodes")
        
        // Update progress
        revisionProgress = .processingFeedback
        
        // Apply accepted changes to resume immediately
        applyAcceptedChanges(feedbackNodes: feedbackNodes, to: resume)
        
        // Filter for nodes that need AI resubmission
        let nodesToRevise = filterNodesForAIResubmission(feedbackNodes)
        
        if nodesToRevise.isEmpty {
            Logger.debug("✅ No nodes require AI resubmission")
            revisionProgress = .completed
            return []
        }
        
        Logger.debug("🔄 Resubmitting \(nodesToRevise.count) nodes to AI")
        revisionProgress = .generatingRevisions
        
        // Create revision prompt from feedback
        let revisionPrompt = createRevisionPrompt(feedbackNodes: nodesToRevise)
        
        // Continue conversation with revision request
        let newRevisions = try await llmService.continueConversationStructured(
            userMessage: revisionPrompt,
            modelId: modelId,
            conversationId: conversationId,
            responseType: RevisionsContainer.self
        )
        
        // Validate new revisions against current resume state
        let validatedRevisions = validateRevisions(newRevisions.revArray, for: resume)
        
        // Filter to only revisions for nodes we requested
        let expectedNodeIds = Set(nodesToRevise.map { $0.id })
        let filteredRevisions = validatedRevisions.filter { expectedNodeIds.contains($0.id) }
        
        self.currentRevisions = filteredRevisions
        self.revisionRounds += 1
        
        revisionProgress = .awaitingUserReview
        Logger.debug("✅ Generated \(filteredRevisions.count) new revisions (round \(revisionRounds))")
        
        return filteredRevisions
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
    /// - Parameters:
    ///   - feedbackNodes: User feedback on revisions
    ///   - resume: The resume to update
    func applyAcceptedChanges(feedbackNodes: [FeedbackNode], to resume: Resume) {
        Logger.debug("✅ Applying accepted changes to resume")
        
        let acceptedActions: Set<PostReviewAction> = [.accepted, .acceptedWithChanges]
        let acceptedNodes = feedbackNodes.filter { acceptedActions.contains($0.actionRequested) }
        
        for node in acceptedNodes {
            if let treeNode = resume.nodes.first(where: { $0.id == node.id }) {
                // Apply the change based on whether it's a title node or value node
                if node.isTitleNode {
                    treeNode.name = node.proposedRevision
                } else {
                    treeNode.value = node.proposedRevision
                }
                
                Logger.debug("✅ Applied change to node \(node.id): \(node.actionRequested.rawValue)")
            } else {
                Logger.debug("⚠️ Could not find tree node with ID: \(node.id)")
            }
        }
        
        // Trigger PDF refresh
        resume.debounceExport()
        
        Logger.debug("✅ Applied \(acceptedNodes.count) accepted changes")
    }
    
    /// Clear conversation state and reset workflow
    func resetWorkflowState() {
        Logger.debug("🔄 Resetting revision workflow state")
        
        if let conversationId = currentConversationId {
            llmService.clearConversation(id: conversationId)
        }
        
        currentConversationId = nil
        currentRevisions = []
        pendingFeedback = []
        revisionRounds = 0
        retryCount = 0
        lastError = nil
        isProcessingRevisions = false
        revisionProgress = .idle
    }
    
    // MARK: - Private Helpers
    
    /// Validate revisions against current resume state
    private func validateRevisions(_ revisions: [ProposedRevisionNode], for resume: Resume) -> [ProposedRevisionNode] {
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