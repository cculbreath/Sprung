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
    private let llm: LLMFacade
    let appState: AppState // Make appState accessible to views
    
    // MARK: - UI State (ViewModel Layer)
    var showResumeRevisionSheet: Bool = false {
        didSet {
            Logger.debug("🔍 [ResumeReviseViewModel] showResumeRevisionSheet changed from \(oldValue) to \(showResumeRevisionSheet)")
            if showResumeRevisionSheet {
                Logger.debug("🔍 [ResumeReviseViewModel] Posting showResumeRevisionSheet notification")
                NotificationCenter.default.post(name: .showResumeRevisionSheet, object: nil)
            } else {
                Logger.debug("🔍 [ResumeReviseViewModel] Posting hideResumeRevisionSheet notification")
                NotificationCenter.default.post(name: .hideResumeRevisionSheet, object: nil)
            }
        }
    }
    var resumeRevisions: [ProposedRevisionNode] = []
    var feedbackNodes: [FeedbackNode] = []
    var approvedFeedbackNodes: [FeedbackNode] = [] // Store approved feedback for multi-round workflows
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
    var currentModelId: String? // Make currentModelId accessible to views
    private(set) var isProcessingRevisions: Bool = false
    
    // AI Resubmission handling (from AiCommsView)
    private var isWaitingForResubmission: Bool = false
    
    // MARK: - Reasoning Stream State (now uses global manager)
    // reasoningStreamManager is accessed via appState.globalReasoningStreamManager
    
    // MARK: - Error Handling
    private(set) var lastError: String?
    private(set) var retryCount: Int = 0
    private let maxRetries: Int = 2
    
    // MARK: - Configuration
    private let revisionTimeout: TimeInterval = 180.0 // 3 minutes
    
    init(llmFacade: LLMFacade, appState: AppState) {
        self.llm = llmFacade
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
    
    /// Start a fresh revision workflow (without clarifying questions)
    /// - Parameters:
    ///   - resume: The resume to revise
    ///   - modelId: The model to use for revisions
    func startFreshRevisionWorkflow(
        resume: Resume,
        modelId: String
    ) async throws {
        
        // Reset UI state
        resumeRevisions = []
        feedbackNodes = []
        currentRevisionNode = nil
        currentFeedbackNode = nil
        aiResubmit = false
        isProcessingRevisions = true
        
        do {
            // Create query for revision workflow
            let query = ResumeApiQuery(resume: resume, saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts"))
            
            // Start conversation with system prompt and user query
            let systemPrompt = query.genericSystemMessage.textContent
            let userPrompt = await query.wholeResumeQueryString()
            
            // Check if model supports reasoning for streaming
            let model = appState.openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false
            
            // Debug logging to track reasoning interface triggering
            Logger.debug("🤖 [startFreshRevisionWorkflow] Model: \(modelId)")
            Logger.debug("🤖 [startFreshRevisionWorkflow] Model found: \(model != nil)")
            Logger.debug("🤖 [startFreshRevisionWorkflow] Model supportedParameters: \(model?.supportedParameters ?? [])")
            Logger.debug("🤖 [startFreshRevisionWorkflow] Supports reasoning: \(supportsReasoning)")
            
            // Defensive check: ensure reasoning modal is hidden for non-reasoning models
            if !supportsReasoning {
                appState.globalReasoningStreamManager.isVisible = false
                appState.globalReasoningStreamManager.clear()
            }
            
            let revisions: RevisionsContainer
            
            if supportsReasoning {
                // Use streaming with reasoning for supported models from the start
                Logger.info("🧠 Using streaming with reasoning for revision generation: \(modelId)")
                
                // Configure reasoning parameters for revision generation using user setting
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(
                    effort: userEffort,
                    includeReasoning: true
                )
                
                // Start streaming conversation with reasoning
                let (conversationId, stream) = try await llm.startConversationStreaming(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
                
                self.currentConversationId = conversationId
                self.currentModelId = modelId
                
                // Process stream and collect full response
                // Clear any previous reasoning text before starting
                appState.globalReasoningStreamManager.clear()
                appState.globalReasoningStreamManager.startReasoning(modelName: modelId)
                var fullResponse = ""
                var collectingJSON = false
                var jsonResponse = ""
                
                for try await chunk in stream {
                    // Handle reasoning content
                    if let reasoningContent = chunk.reasoningContent {
                        appState.globalReasoningStreamManager.reasoningText += reasoningContent
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
                    
                    // Handle completion
                    if chunk.isFinished {
                        appState.globalReasoningStreamManager.isStreaming = false
                        // Hide the reasoning modal when streaming completes
                        appState.globalReasoningStreamManager.isVisible = false
                    }
                }
                
                // Parse the JSON response
                let responseText = jsonResponse.isEmpty ? fullResponse : jsonResponse
                revisions = try parseJSONFromText(responseText, as: RevisionsContainer.self)
                
            } else {
                // Use non-streaming structured output for models without reasoning
                Logger.info("📝 Using non-streaming structured output for revision generation: \(modelId)")
                
                // Start conversation to maintain state for potential resubmission
                let (conversationId, _) = try await llm.startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId
                )
                
                self.currentConversationId = conversationId
                self.currentModelId = modelId
                
                // Get structured response from the conversation
                revisions = try await llm.continueConversationStructured(
                    userMessage: "Please provide the revision suggestions in the specified JSON format.",
                    modelId: modelId,
                    conversationId: conversationId,
                    as: RevisionsContainer.self,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
            }
            
            // Validate and process the revisions
            let validatedRevisions = validateRevisions(revisions.revArray, for: resume)
            
            // Set up the UI state for revision review
            await setupRevisionsForReview(validatedRevisions)
            
        } catch {
            isProcessingRevisions = false
            throw error
        }
    }
    
    /// Continue an existing conversation and generate revisions
    /// This is used when ClarifyingQuestionsViewModel hands off the conversation
    /// - Parameters:
    ///   - conversationId: The existing conversation ID from ClarifyingQuestionsViewModel
    ///   - resume: The resume being revised
    ///   - modelId: The model to continue with
    func continueConversationAndGenerateRevisions(
        conversationId: UUID,
        resume: Resume,
        modelId: String
    ) async throws {
        // Store the conversation context
        currentConversationId = conversationId
        currentModelId = modelId
        isProcessingRevisions = true
        
        do {
            // Create revision request with editable nodes only (context already established)
            let query = ResumeApiQuery(resume: resume, saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts"))
            let revisionRequestPrompt = await query.multiTurnRevisionPrompt()
            
            // Check if model supports reasoning for streaming
            let model = appState.openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false
            
            // Debug logging to track reasoning interface triggering
            Logger.debug("🤖 [continueConversationAndGenerateRevisions] Model: \(modelId)")
            Logger.debug("🤖 [continueConversationAndGenerateRevisions] Model found: \(model != nil)")
            Logger.debug("🤖 [continueConversationAndGenerateRevisions] Supports reasoning: \(supportsReasoning)")
            
            // Only show reasoning modal for models that support reasoning
            if supportsReasoning {
                // Clear any previous reasoning content and reset state
                appState.globalReasoningStreamManager.clear()
                
                // Show reasoning modal for reasoning-enabled models
                appState.globalReasoningStreamManager.modelName = modelId
                appState.globalReasoningStreamManager.isVisible = true
            } else {
                // Defensive check: ensure reasoning modal is hidden for non-reasoning models
                appState.globalReasoningStreamManager.isVisible = false
                appState.globalReasoningStreamManager.clear()
            }
            
            let revisions: RevisionsContainer
            
            if supportsReasoning {
                // Use streaming with reasoning for supported models
                Logger.info("🧠 Using streaming with reasoning for revision continuation: \(modelId)")
                
                // Configure reasoning parameters using user setting
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(
                    effort: userEffort,
                    includeReasoning: true
                )
                
                revisions = try await streamRevisionGeneration(
                    userMessage: revisionRequestPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    reasoning: reasoning
                )
            } else {
                // Use non-streaming for models without reasoning
                Logger.info("📝 Using non-streaming structured output for revision continuation: \(modelId)")
                
                revisions = try await llm.continueConversationStructured(
                    userMessage: revisionRequestPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    as: RevisionsContainer.self,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
            }
            
            // Process and validate revisions
            let validatedRevisions = validateRevisions(revisions.revArray, for: resume)
            
            // Set up the UI state for revision review
            await setupRevisionsForReview(validatedRevisions)
            
            Logger.debug("✅ Conversation handoff complete: \(validatedRevisions.count) revisions ready for review")
            
        } catch {
            Logger.error("Error continuing conversation for revisions: \(error.localizedDescription)")
            isProcessingRevisions = false
            throw error
        }
    }
    
    
    /// Set up revisions for UI review
    /// - Parameter revisions: The validated revisions to review
    @MainActor
    private func setupRevisionsForReview(_ revisions: [ProposedRevisionNode]) async {
        Logger.debug("🔍 [ResumeReviseViewModel] setupRevisionsForReview called with \(revisions.count) revisions")
        Logger.debug("🔍 [ResumeReviseViewModel] Current instance address: \(String(describing: Unmanaged.passUnretained(self).toOpaque()))")
        Logger.debug("🔍 [ResumeReviseViewModel] appState.resumeReviseViewModel address: \(appState.resumeReviseViewModel.map { String(describing: Unmanaged.passUnretained($0).toOpaque()) } ?? "nil")")
        
        // Set up revisions in the UI state
        resumeRevisions = revisions
        feedbackNodes = []
        feedbackIndex = 0
        
        // Set up the first revision for review
        if !revisions.isEmpty {
            currentRevisionNode = revisions[0]
            currentFeedbackNode = revisions[0].createFeedbackNode()
        }
        
        // Ensure reasoning modal is hidden before showing revision review
        Logger.debug("🔍 [ResumeReviseViewModel] Hiding reasoning modal")
        appState.globalReasoningStreamManager.isVisible = false
        appState.globalReasoningStreamManager.clear()
        
        // Show the revision review UI
        Logger.debug("🔍 [ResumeReviseViewModel] Setting showResumeRevisionSheet = true")
        showResumeRevisionSheet = true
        isProcessingRevisions = false
        
        Logger.debug("🔍 [ResumeReviseViewModel] After setting - showResumeRevisionSheet = \(showResumeRevisionSheet)")
        Logger.debug("🔍 [ResumeReviseViewModel] Is this instance the same as appState.resumeReviseViewModel? \(appState.resumeReviseViewModel === self)")
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
        
        // Capability gating centralized in facade (handled elsewhere)
        
        // Create clarifying questions prompt using the generic system message
        let systemPrompt = query.genericSystemMessage.textContent
        let userContext = await query.wholeResumeQueryString()
        
        // Request clarifying questions
        let questionsRequest: ClarifyingQuestionsRequest = try await llm.executeStructured(
            prompt: "\(systemPrompt)\n\nResume Context:\n\(userContext)",
            modelId: modelId,
            as: ClarifyingQuestionsRequest.self,
            temperature: nil
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
        // Merge approved feedback from previous rounds with current feedback
        let allFeedbackNodes = approvedFeedbackNodes + feedbackNodes
        
        // Log statistics and apply changes using all feedback
        allFeedbackNodes.logFeedbackStatistics()
        allFeedbackNodes.applyAcceptedChanges(to: resume)
        
        // Check for resubmission using all feedback
        let nodesToResubmit = allFeedbackNodes.nodesRequiringAIResubmission
        
        if !nodesToResubmit.isEmpty {
            Logger.debug("Resubmitting \(nodesToResubmit.count) nodes to AI...")
            // Keep only nodes that need AI intervention for the next round
            feedbackNodes = nodesToResubmit
            nodesToResubmit.logResubmissionSummary()
            
            // Start AI resubmission workflow
            startAIResubmission(with: resume)
        } else {
            Logger.debug("No nodes need resubmission. All changes applied, dismissing sheet...")
            Logger.debug("🔍 [completeReviewWorkflow] Setting showResumeRevisionSheet = false")
            Logger.debug("🔍 [completeReviewWorkflow] Current showResumeRevisionSheet value: \(showResumeRevisionSheet)")
            
            // Clear all state before dismissing
            approvedFeedbackNodes = []
            feedbackNodes = []
            resumeRevisions = []
            
            showResumeRevisionSheet = false
            Logger.debug("🔍 [completeReviewWorkflow] After setting - showResumeRevisionSheet = \(showResumeRevisionSheet)")
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
                
                // Actually perform the AI resubmission
                await performAIResubmission(with: resume)
                
            } catch {
                Logger.debug("Error rendering resume for AI resubmission: \(error)")
                await MainActor.run {
                    aiResubmit = false
                }
            }
        }
    }
    
    /// Perform the actual AI resubmission with feedback nodes requiring revision
    @MainActor
    private func performAIResubmission(with resume: Resume) async {
        guard let conversationId = currentConversationId else {
            Logger.error("No conversation ID available for AI resubmission")
            aiResubmit = false
            return
        }
        
        // Use the same model as the original conversation
        guard let modelId = currentModelId else {
            Logger.error("No model available for AI resubmission")
            aiResubmit = false
            return
        }
        
        // Check if model supports reasoning to determine UI behavior
        let model = appState.openRouterService.findModel(id: modelId)
        let supportsReasoning = model?.supportsReasoning ?? false
        
        // For reasoning models, temporarily hide the review sheet
        if supportsReasoning {
            Logger.debug("🔍 Temporarily hiding review sheet for reasoning modal")
            showResumeRevisionSheet = false
        }
        
        do {
            // Create revision prompt from feedback nodes requiring resubmission
            let nodesToResubmit = feedbackNodes.filter { node in
                let aiActions: Set<PostReviewAction> = [.revise, .mandatedChange, .mandatedChangeNoComment, .rewriteNoComment]
                return aiActions.contains(node.actionRequested)
            }
            
            Logger.debug("🔄 Resubmitting \(nodesToResubmit.count) nodes to AI")
            
            let revisionPrompt = createRevisionPrompt(feedbackNodes: nodesToResubmit)
            
            // Check if model supports reasoning for streaming during resubmission
            let model = appState.openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false
            
            let revisions: RevisionsContainer
            
            if supportsReasoning {
                // Use streaming with reasoning for supported models
                Logger.info("🧠 Using streaming with reasoning for AI resubmission: \(modelId)")
                
                // Configure reasoning parameters using user setting
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(
                    effort: userEffort,
                    includeReasoning: true
                )
                
                revisions = try await streamRevisionGeneration(
                    userMessage: revisionPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    reasoning: reasoning
                )
            } else {
                // Use non-streaming for models without reasoning
                revisions = try await llmService.continueConversationStructured(
                    userMessage: revisionPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    responseType: RevisionsContainer.self,
                    jsonSchema: ResumeApiQuery.revNodeArraySchema
                )
            }
            
            // Validate and process the new revisions
            let validatedRevisions = validateRevisions(revisions.revArray, for: resume)
            
            // Get IDs of nodes that were resubmitted for updating
            let resubmittedNodeIds = Set(nodesToResubmit.map { $0.id })
            
            Logger.debug("🔍 Resubmitted \(nodesToResubmit.count) nodes, got back \(validatedRevisions.count) revisions")
            Logger.debug("🔍 Resubmitted node IDs: \(resubmittedNodeIds)")
            Logger.debug("🔍 Received revision IDs: \(validatedRevisions.map { $0.id })")
            
            // Filter validated revisions to only include ones that were actually requested for resubmission
            let requestedRevisions = validatedRevisions.filter { revision in
                resubmittedNodeIds.contains(revision.id)
            }
            
            if requestedRevisions.count != validatedRevisions.count {
                Logger.warning("⚠️ AI returned \(validatedRevisions.count) revisions but only \(requestedRevisions.count) were requested")
            }
            
            // For the second round, show ONLY the new revisions that need review
            // Keep approved feedback for final application, but don't show in UI
            let approvedFeedbackForLater = feedbackNodes.filter { feedback in
                !resubmittedNodeIds.contains(feedback.id)
            }
            
            // Replace arrays with only the new revisions requiring review
            resumeRevisions = requestedRevisions
            feedbackNodes = [] // Start fresh for new revisions
            
            // Reset to first revision (now only showing new ones)
            feedbackIndex = 0
            
            // Set up the first NEW revision for review
            if !resumeRevisions.isEmpty {
                currentRevisionNode = resumeRevisions[0]
                currentFeedbackNode = resumeRevisions[0].createFeedbackNode()
            }
            
            // Store approved feedback for final application
            // We'll need to merge this back when completing the workflow
            self.approvedFeedbackNodes = approvedFeedbackForLater
            
            // Clear loading state
            aiResubmit = false
            
            // For reasoning models, show the review sheet again
            if supportsReasoning && !resumeRevisions.isEmpty {
                Logger.debug("🔍 Showing review sheet again after reasoning modal")
                showResumeRevisionSheet = true
            }
            
            Logger.debug("✅ AI resubmission complete: \(validatedRevisions.count) new revisions ready for review")
            
        } catch {
            Logger.error("Error in AI resubmission: \(error.localizedDescription)")
            aiResubmit = false
            
            // Ensure sheet is shown again on error for reasoning models
            if supportsReasoning {
                showResumeRevisionSheet = true
            }
        }
    }
    
    /// Initialize updateNodes for the review workflow
    func initializeUpdateNodes(for resume: Resume) {
        updateNodes = resume.getUpdatableNodes()
    }
    
    /// Navigate to previous revision node
    func navigateToPrevious() {
        guard feedbackIndex > 0 else { 
            Logger.debug("Cannot navigate to previous: already at first revision")
            return 
        }
        
        feedbackIndex -= 1
        
        // Bounds check for resumeRevisions array
        guard feedbackIndex < resumeRevisions.count else {
            Logger.error("Navigation error: feedbackIndex \(feedbackIndex) out of bounds for resumeRevisions count \(resumeRevisions.count)")
            feedbackIndex = min(feedbackIndex, resumeRevisions.count - 1)
            return
        }
        
        currentRevisionNode = resumeRevisions[feedbackIndex]
        
        // Restore or create feedback node for this revision
        if feedbackIndex < feedbackNodes.count {
            currentFeedbackNode = feedbackNodes[feedbackIndex]
            // Restore UI state based on saved feedback
            restoreUIStateFromFeedbackNode(feedbackNodes[feedbackIndex])
        } else {
            currentFeedbackNode = currentRevisionNode?.createFeedbackNode()
            // Reset UI state for new feedback
            resetUIState()
        }
        
        Logger.debug("Navigated to previous revision: \(feedbackIndex + 1)/\(resumeRevisions.count)")
    }
    
    /// Navigate to next revision node
    func navigateToNext() {
        guard feedbackIndex < resumeRevisions.count - 1 else { 
            Logger.debug("Cannot navigate to next: already at last revision")
            return 
        }
        
        // Save current feedback node if it exists and isn't already saved
        if let currentFeedbackNode = currentFeedbackNode, feedbackIndex >= feedbackNodes.count {
            feedbackNodes.append(currentFeedbackNode)
        }
        
        feedbackIndex += 1
        
        // Bounds check for resumeRevisions array
        guard feedbackIndex < resumeRevisions.count else {
            Logger.error("Navigation error: feedbackIndex \(feedbackIndex) out of bounds for resumeRevisions count \(resumeRevisions.count)")
            feedbackIndex = resumeRevisions.count - 1
            return
        }
        
        currentRevisionNode = resumeRevisions[feedbackIndex]
        
        // Restore or create feedback node for this revision
        if feedbackIndex < feedbackNodes.count {
            currentFeedbackNode = feedbackNodes[feedbackIndex]
            // Restore UI state based on saved feedback
            restoreUIStateFromFeedbackNode(feedbackNodes[feedbackIndex])
        } else {
            currentFeedbackNode = currentRevisionNode?.createFeedbackNode()
            // Reset UI state for new feedback
            resetUIState()
        }
        
        Logger.debug("Navigated to next revision: \(feedbackIndex + 1)/\(resumeRevisions.count)")
    }
    
    /// Restore UI state from a saved feedback node
    private func restoreUIStateFromFeedbackNode(_ feedbackNode: FeedbackNode) {
        // Check if this node had commenting active based on action taken
        let commentingActions: Set<PostReviewAction> = [.revise, .mandatedChange]
        let moreCommentingActions: Set<PostReviewAction> = [.mandatedChangeNoComment]
        
        if commentingActions.contains(feedbackNode.actionRequested) && !feedbackNode.reviewerComments.isEmpty {
            isCommenting = true
            isMoreCommenting = false
        } else if moreCommentingActions.contains(feedbackNode.actionRequested) && !feedbackNode.reviewerComments.isEmpty {
            isCommenting = false
            isMoreCommenting = true
        } else {
            isCommenting = false
            isMoreCommenting = false
        }
        
        // Always reset editing state when navigating
        isEditingResponse = false
    }
    
    /// Check if a node was accepted (for button illumination)
    func isNodeAccepted(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        let acceptedActions: Set<PostReviewAction> = [.accepted, .acceptedWithChanges, .noChange]
        return acceptedActions.contains(feedbackNode.actionRequested)
    }
    
    /// Check if a node was rejected with comments (for thumbs down illumination)
    func isNodeRejectedWithComments(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .revise
    }
    
    /// Check if a node was rejected without comments (for trash button illumination)
    func isNodeRejectedWithoutComments(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .rewriteNoComment
    }
    
    /// Check if a node was restored to original (for restore button illumination)
    func isNodeRestored(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .restored
    }
    
    /// Check if a node was edited (for edit button illumination)
    func isNodeEdited(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .acceptedWithChanges
    }
    
    /// Check if a node had change requested (for unchanged values - pencil button illumination)
    func isChangeRequested(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        let changeRequestedActions: Set<PostReviewAction> = [.mandatedChange, .mandatedChangeNoComment]
        return changeRequestedActions.contains(feedbackNode.actionRequested)
    }
    
    /// Reset UI state for new/fresh feedback nodes
    private func resetUIState() {
        isCommenting = false
        isMoreCommenting = false
        isEditingResponse = false
    }
    
    /// Clear all action states (for radio button behavior)
    func clearActionStates() {
        isCommenting = false
        isMoreCommenting = false
        isEditingResponse = false
    }
    
    
    /// Clear conversation state and reset workflow
    func resetWorkflowState() {
        Logger.debug("🔄 Resetting revision workflow state")
        
        if let conversationId = currentConversationId {
            llmService.clearConversation(id: conversationId)
        }
        
        currentConversationId = nil
        currentModelId = nil
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
    
    /// Stream revision generation with reasoning support
    private func streamRevisionGeneration(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        reasoning: OpenRouterReasoning
    ) async throws -> RevisionsContainer {
        
        // Start streaming
        let stream = llm.continueConversationStreaming(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            reasoning: reasoning,
            jsonSchema: ResumeApiQuery.revNodeArraySchema
        )
        
        // Process stream and collect full response
        // Start reasoning stream (content already cleared in parent method)
        appState.globalReasoningStreamManager.startReasoning(modelName: modelId)
        var fullResponse = ""
        var collectingJSON = false
        var jsonResponse = ""
        
        for try await chunk in stream {
            // Handle reasoning content
            if let reasoningContent = chunk.reasoningContent {
                appState.globalReasoningStreamManager.reasoningText += reasoningContent
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
            
            // Handle completion
            if chunk.isFinished {
                appState.globalReasoningStreamManager.isStreaming = false
                // Hide the reasoning modal when streaming completes
                appState.globalReasoningStreamManager.isVisible = false
            }
        }
        
        // Parse the JSON response
        let responseText = jsonResponse.isEmpty ? fullResponse : jsonResponse
        return try parseJSONFromText(responseText, as: RevisionsContainer.self)
    }
    
    /// Parse JSON from text content with fallback strategies
    private func parseJSONFromText<T: Codable>(_ text: String, as type: T.Type) throws -> T {
        Logger.debug("🔍 Attempting to parse JSON from text: \(text.prefix(500))...")
        
        // First try direct parsing if the entire text is JSON
        if let jsonData = text.data(using: .utf8) {
            do {
                let result = try JSONDecoder().decode(type, from: jsonData)
                Logger.info("✅ Direct JSON parsing successful")
                return result
            } catch {
                Logger.debug("❌ Direct JSON parsing failed: \(error)")
                Logger.error("🚨 [JSON Debug] Full LLM response that failed direct parsing:")
                Logger.error("📄 [JSON Debug] Response length: \(text.count) characters")
                Logger.error("📄 [JSON Debug] Full response text:")
                Logger.error("--- START RESPONSE ---")
                Logger.error("\(text)")
                Logger.error("--- END RESPONSE ---")
            }
        }
        
        // Try to extract JSON from text (look for JSON between ```json and ``` or just {...})
        let cleanedText = extractJSONFromText(text)
        if let jsonData = cleanedText.data(using: .utf8) {
            do {
                let result = try JSONDecoder().decode(type, from: jsonData)
                Logger.info("✅ Extracted JSON parsing successful")
                return result
            } catch {
                Logger.debug("❌ Extracted JSON parsing failed: \(error)")
                Logger.error("🚨 [JSON Debug] Extracted text that failed parsing:")
                Logger.error("📄 [JSON Debug] Extracted length: \(cleanedText.count) characters")
                Logger.error("📄 [JSON Debug] Extracted text:")
                Logger.error("--- START EXTRACTED ---")
                Logger.error("\(cleanedText)")
                Logger.error("--- END EXTRACTED ---")
                Logger.error("🔍 [JSON Debug] Expected type: \(String(describing: type))")
                Logger.error("🔍 [JSON Debug] Decoding error details: \(error)")
            }
        } else {
            Logger.error("🚨 [JSON Debug] Could not convert extracted text to UTF-8 data")
            Logger.error("📄 [JSON Debug] Original text length: \(text.count)")
            Logger.error("📄 [JSON Debug] Extracted text: '\(cleanedText)'")
        }
        
        // If JSON parsing fails, include the full response in the error for debugging
        let fullResponsePreview = text.count > 1000 ? "\(text.prefix(1000))...[truncated]" : text
        let errorMessage = "Could not parse JSON from response. Full response: \(fullResponsePreview)"
        throw LLMError.decodingFailed(NSError(domain: "ResumeReviseViewModel", code: 1, userInfo: [
            NSLocalizedDescriptionKey: errorMessage,
            "fullResponse": text
        ]))
    }
    
    /// Extract JSON from text that may contain other content
    private func extractJSONFromText(_ text: String) -> String {
        // Look for JSON between code blocks
        if let range = text.range(of: "```json") {
            let afterStart = text[range.upperBound...]
            if let endRange = afterStart.range(of: "```") {
                return String(afterStart[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Look for standalone JSON object
        if let startRange = text.range(of: "{") {
            var braceCount = 1
            var index = text.index(after: startRange.lowerBound)
            
            while index < text.endIndex && braceCount > 0 {
                let char = text[index]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                }
                index = text.index(after: index)
            }
            
            if braceCount == 0 {
                let jsonRange = startRange.lowerBound..<index
                return String(text[jsonRange])
            }
        }
        
        return text
    }
}

// MARK: - Supporting Types



// MARK: - Note: Using existing types from AITypes.swift and ResumeUpdateNode.swift
// - RevisionsContainer (with revArray property)
// - ClarifyingQuestionsRequest 
// - ClarifyingQuestion
// - QuestionAnswer
