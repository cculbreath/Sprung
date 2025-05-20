//  AiCommsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/9/24.
//

import AppKit // Needed for NSEvent modifier‑key inspection on macOS
import AVFoundation
import Foundation
import SwiftUI

struct AiCommsView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @State private var q: ResumeApiQuery
    @State private var chatProvider: ResumeChatProvider
    @State private var revisions: [ProposedRevisionNode] = []
    @State private var currentRevNode: ProposedRevisionNode? = nil
    @State var currentFeedbackNode: FeedbackNode? = nil
    @State private var isLoading = false
    @State private var sheetOn: Bool = false
    @State private var aiResub: Bool = false
    @Binding var myRes: Resume?
    @State private var fbnodes: [FeedbackNode] = []
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    @State private var retryCount: Int = 0
    @State private var isRetrying: Bool = false

    // TTS related state
    @Binding var ttsEnabled: Bool
    @Binding var ttsVoice: String

    // Store references to clients for AI operations
    private let openAIClient: OpenAIClientProtocol

    init(
        openAIClient: OpenAIClientProtocol,
        query: ResumeApiQuery,
        res: Binding<Resume?>,
        ttsEnabled: Binding<Bool> = .constant(false),
        ttsVoice: Binding<String> = .constant("nova")
    ) {
        // Initialize with abstraction layer client
        _chatProvider = State(initialValue: ResumeChatProvider(client: openAIClient))
        self.openAIClient = openAIClient
        _q = State(initialValue: query)
        _myRes = res
        _ttsEnabled = ttsEnabled
        _ttsVoice = ttsVoice
    }

    var body: some View {
        execQuery
            .sheet(isPresented: $sheetOn) {} content: {
                if sheetOn {
                    ReviewView(
                        revisionArray: $revisions,
                        feedbackArray: $fbnodes,
                        currentFeedbackNode: $currentFeedbackNode,
                        currentRevNode: $currentRevNode,
                        sheetOn: $sheetOn,
                        selRes: $myRes,
                        aiResub: $aiResub
                    )
                    .frame(minWidth: 650)
                }
            }
            .alert("API Request Error", isPresented: $showError) {
                Button("OK") {
                    // Reset state when error is acknowledged
                    aiResub = false
                    sheetOn = false
                    isLoading = false
                }
            } message: {
                Text(errorMessage)
            }
            .onChange(of: chatProvider.lastRevNodeArray) { _, newValue in
                Logger.debug("\nReceived \(newValue.count) revision nodes from AI")

                // Create a mutable copy of the array that we can filter
                var processedRevisions = newValue

                // For revision rounds, filter out any nodes that weren't in our feedback list
                if aiResub && !fbnodes.isEmpty {
                    let expectedNodeIds = Set(fbnodes.map { $0.id })
                    let filteredRevNodes = processedRevisions.filter { revNode in
                        let shouldInclude = expectedNodeIds.contains(revNode.id)
                        if !shouldInclude {
                            Logger.debug("Removing unexpected node ID \(revNode.id) from AI response (not in feedback list)")
                        }
                        return shouldInclude
                    }

                    if filteredRevNodes.count < processedRevisions.count {
                        Logger.debug("Filtered out \(processedRevisions.count - filteredRevNodes.count) unexpected revision nodes")
                        // Update our mutable copy
                        processedRevisions = filteredRevNodes
                    }
                }

                // Debug - check for potentially deleted nodes
                if let myRes = myRes {
                    let currentNodeIds = Set(myRes.nodes.map { $0.id })
                    for revNode in processedRevisions {
                        if !currentNodeIds.contains(revNode.id) {
                            Logger.debug("WARNING: Revision node with ID \(revNode.id) references a node that no longer exists in the resume!")
                            Logger.debug("  - Content: '\(revNode.oldValue)' -> '\(revNode.newValue)'")
                            Logger.debug("  - Tree path: \(revNode.treePath)")
                        }
                    }
                }

                // Validate and fix the revision nodes
                let validatedRevisions = validateRevs(res: myRes, revs: processedRevisions) ?? []
                Logger.debug("After validation: \(validatedRevisions.count) revision nodes (from original \(processedRevisions.count))")

                // Reset arrays - IMPORTANT: this prevents accumulation of nodes
                fbnodes = []

                sheetOn = true
                revisions = validatedRevisions
                
                // Check if revisions array is not empty before accessing the first element
                if !revisions.isEmpty {
                    currentRevNode = revisions[0]
                    currentFeedbackNode = FeedbackNode(
                        id: currentRevNode!.id,
                        originalValue: currentRevNode!.oldValue,
                        proposedRevision: currentRevNode!.newValue,
                        actionRequested: .unevaluated,
                        reviewerComments: "",
                        isTitleNode: currentRevNode!.isTitleNode
                    )
                } else {
                    // Handle the case when no revisions are available
                    currentRevNode = nil
                    currentFeedbackNode = nil
                    Logger.debug("No valid revision nodes available")
                }
                aiResub = false
                fbnodes = []
            }
            .onChange(of: aiResub) { _, newValue in
                if newValue {
                    // Reset retry count when starting a new request
                    if !isRetrying {
                        retryCount = 0
                    }

                    chatAction(hasRevisions: true)

                    // Safety timeout to dismiss the review view if AI request takes too long
                    DispatchQueue.main.asyncAfter(deadline: .now() + 180) { // 3 minutes timeout
                        if isLoading && aiResub {
                            // If this is the first attempt, retry once
                            if retryCount == 0 {
                                retryCount += 1
                                isRetrying = true

                                // Retry the request
                                chatAction(hasRevisions: true)

                                // Set another timeout for the retry
                                DispatchQueue.main.asyncAfter(deadline: .now() + 180) { // 3 minutes for retry
                                    if isLoading && aiResub {
                                        self.showError = true
                                        self.errorMessage = "The AI request is still taking longer than expected. Please try again later."
                                        aiResub = false
                                        sheetOn = false
                                        isLoading = false
                                        isRetrying = false
                                    }
                                }
                            } else {
                                // Already retried once, show error
                                self.showError = true
                                self.errorMessage = "The AI request is taking longer than expected. Please try again later."
                                aiResub = false
                                sheetOn = false
                                isLoading = false
                                isRetrying = false
                            }
                        }
                    }
                }
            }
    }

    var execQuery: some View {
        HStack(spacing: 8) {
            VStack {
                if !isLoading {
                    if
                        (myRes?.rootNode?.aiStatusChildren ?? 0)
                        > 0
                    {
                        Button(action: {
                            chatAction()
                        }) {
                            Image("ai-squiggle")
                                .font(.system(size: 20, weight: .regular))
                        }
                        .help("Create new Résumé")
                    } else {
                        Image("ai-squiggle.slash").font(.system(size: 20, weight: .regular)).help("Select fields for ai update")
                    }
                } else {
                    VStack(spacing: 4) {
                        ProgressView().scaleEffect(0.75, anchor: .center)
                        if isRetrying {
                            Text("Retrying request...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

    // Validation function for revisions
    func validateRevs(res: Resume?, revs: [ProposedRevisionNode]) -> [ProposedRevisionNode]? {
        var validRevs = revs
        if let myRes = res {
            let updateNodes = myRes.getUpdatableNodes()

            // Filter out revisions for nodes that no longer exist in the resume
            let currentNodeIds = Set(myRes.nodes.map { $0.id })
            let initialCount = validRevs.count
            validRevs = validRevs.filter { revNode in
                let exists = currentNodeIds.contains(revNode.id)
                if !exists {
                    Logger.debug("Filtering out revision for non-existent node with ID: \(revNode.id)")
                }
                return exists
            }
            if validRevs.count < initialCount {
                Logger.debug("Removed \(initialCount - validRevs.count) revisions for non-existent nodes")
            }

            // First pass: validate and update existing revisions
            for (index, item) in validRevs.enumerated() {
                // Check by ID first
                if let matchedNode = updateNodes.first(where: { $0["id"] as? String == item.id }) {
                    // If we have a match but empty oldValue, populate it based on isTitleNode
                    if validRevs[index].oldValue.isEmpty {
                        // For title nodes, use the name property
                        let isTitleNode = matchedNode["isTitleNode"] as? Bool ?? false
                        if isTitleNode {
                            validRevs[index].oldValue = matchedNode["name"] as? String ?? ""
                        } else {
                            validRevs[index].oldValue = matchedNode["value"] as? String ?? ""
                        }
                        validRevs[index].isTitleNode = isTitleNode
                    }
                    continue
                } else if let matchedByValue = updateNodes.first(where: { $0["value"] as? String == item.oldValue }), let id = matchedByValue["id"] as? String {
                    // Update revision's ID if matched by value
                    validRevs[index].id = id

                    // Make sure to preserve isTitleNode when matching by value
                    validRevs[index].isTitleNode = matchedByValue["isTitleNode"] as? Bool ?? false
                } else if !item.treePath.isEmpty {
                    let treePath = item.treePath
                    // If we have a treePath, try to find a matching node by that path
                    let components = treePath.components(separatedBy: " > ")
                    if components.count > 1 {
                        // Find nodes that might be at that path
                        let potentialMatches = updateNodes.filter { node in
                            let nodePath = node["tree_path"] as? String ?? ""
                            return nodePath == treePath || nodePath.hasSuffix(treePath)
                        }

                        if let match = potentialMatches.first {
                            // We found a match, update the oldValue and ID
                            validRevs[index].id = match["id"] as? String ?? item.id
                            let isTitleNode = match["isTitleNode"] as? Bool ?? false
                            if isTitleNode {
                                validRevs[index].oldValue = match["name"] as? String ?? ""
                            } else {
                                validRevs[index].oldValue = match["value"] as? String ?? ""
                            }
                            validRevs[index].isTitleNode = isTitleNode
                        }
                    }
                }

                // As a last resort, try to find the node in the resume's nodes by ID
                if validRevs[index].oldValue.isEmpty && !validRevs[index].id.isEmpty {
                    if let treeNode = myRes.nodes.first(where: { $0.id == validRevs[index].id }) {
                        if validRevs[index].isTitleNode {
                            validRevs[index].oldValue = treeNode.name
                        } else {
                            validRevs[index].oldValue = treeNode.value
                        }
                    }
                }
            }

            // DISABLING node splitting for now - this appears to be causing multiplication of nodes
            // Second pass: split nodes with both name and value into two separate nodes
            // var additionalNodes: [ProposedRevisionNode] = []
            //
            // for treeNode in myRes.nodes.filter({ $0.status == .aiToReplace }) {
            //    if !treeNode.name.isEmpty && !treeNode.value.isEmpty {
            //        // ... node splitting logic (removed for now)
            //    }
            // }
            //
            // // Add the additional nodes to the validation result
            // validRevs.append(contentsOf: additionalNodes)

            Logger.debug("Final count after validation: \(validRevs.count) (started with \(revs.count))")
            return validRevs
        }
        return nil
    }

    /// Uses TTS to speak the AI revision suggestions

    func chatAction(hasRevisions: Bool = false) {
        if let jobApp = jobAppStore.selectedApp {
            jobApp.status = .inProgress
        }

        Task {
            isLoading = true

            do {
                // Prepare messages for API call using our abstraction layer
                if !hasRevisions {
                    // For a new resume generation, we want to clear conversation context
                    if let myRes = myRes {
                        Logger.debug("Starting new resume generation - clearing conversation context")
                        myRes.clearConversationContext()
                    }

                    // Set up system and user messages for initial query
                    let userPromptContent = await q.wholeResumeQueryString() // Await the async prompt generation
                    
                    // Validate the query content
                    if userPromptContent.isEmpty {
                        Logger.debug("⚠️ WARNING: wholeResumeQueryString returned empty content!")
                    } else {
                        Logger.debug("✅ wholeResumeQueryString returned content of length: \(userPromptContent.count) chars")
                    }
                    
                    // Ensure we have a valid system message
                    if q.genericSystemMessage.content.isEmpty {
                        Logger.debug("⚠️ WARNING: genericSystemMessage has empty content!")
                    } else {
                        Logger.debug("✅ genericSystemMessage has content of length: \(q.genericSystemMessage.content.count) chars")
                    }
                    
                    let updatedProvider = chatProvider
                    updatedProvider.genericMessages = [
                        q.genericSystemMessage,
                        ChatMessage(role: .user, content: userPromptContent), // Use awaited content
                    ]
                    chatProvider = updatedProvider
                } else {
                    // Start a new message list for the revision round.
                    // With ChatCompletions API, context is managed locally.
                    let revisionUserPromptContent = await q.revisionPrompt(fbnodes) // Await the async prompt generation
                    let updatedProvider = chatProvider
                    updatedProvider.genericMessages = [
                        q.genericSystemMessage,
                        ChatMessage(role: .user, content: revisionUserPromptContent), // Use awaited content
                    ]
                    chatProvider = updatedProvider
                }

                // Get the model string
                let modelString = OpenAIModelFetcher.getPreferredModelString()
                
                // Get API key
                let openAiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
                
                // Important check: Verify that we actually have messages to send
                if chatProvider.genericMessages.isEmpty {
                    Logger.debug("❌ CRITICAL ERROR: No messages to send to LLM! Attempting to recover...")
                    
                    // Try to reconstruct the messages
                    let systemMessage = q.genericSystemMessage
                    let userContent = !hasRevisions ? await q.wholeResumeQueryString() : await q.revisionPrompt(fbnodes)
                    
                    if userContent.isEmpty {
                        Logger.debug("❌ Failed to recover: User content is empty")
                        throw NSError(domain: "AiCommsError", code: 1001, 
                            userInfo: [NSLocalizedDescriptionKey: "Failed to generate prompt content"])
                    } else {
                        Logger.debug("✅ Successfully recovered prompt content: \(userContent.count) chars")
                        let updatedProvider = chatProvider
                        updatedProvider.genericMessages = [
                            systemMessage,
                            ChatMessage(role: .user, content: userContent)
                        ]
                        chatProvider = updatedProvider
                    }
                } else {
                    Logger.debug("✅ Message queue contains \(chatProvider.genericMessages.count) messages")
                    for (i, msg) in chatProvider.genericMessages.enumerated() {
                        Logger.debug("   Message[\(i)]: Role=\(msg.role), Content length=\(msg.content.count) chars")
                    }
                }
                
                // If the model selection has changed, we need to update our client
                if modelString != chatProvider.lastModelUsed {
                    Logger.debug("Switching to OpenAI client for model: \(modelString)")
                    // Create a new client for OpenAI
                    if let openAIClient = OpenAIClientFactory.createClient(apiKey: openAiKey) {
                        // Important: preserve the message queue when switching clients
                        let messages = chatProvider.genericMessages
                        chatProvider = ResumeChatProvider(client: openAIClient)
                        chatProvider.genericMessages = messages
                        chatProvider.lastModelUsed = modelString
                    } else {
                        Logger.debug("❌ Failed to create OpenAI client with provided API key")
                        throw NSError(domain: "OpenAIError", 
                                     code: 1002, 
                                     userInfo: [NSLocalizedDescriptionKey: "Failed to create OpenAI client. Please check your API key."])
                    }
                    }
                
                // Execute the API call with our new Responses API method
                Logger.debug("Starting API call with model: \(modelString)")
                try await chatProvider.startChat(messages: chatProvider.genericMessages,
                                                 resume: myRes,
                                                 continueConversation: hasRevisions)
                Logger.debug("API call completed successfully")

                // Check for error messages from the chat provider
                if !chatProvider.errorMessage.isEmpty {
                    throw NSError(domain: "OpenAIError",
                                  code: 1001,
                                  userInfo: [NSLocalizedDescriptionKey: chatProvider.errorMessage])
                }
            } catch {
                // Update error state and show alert
                await MainActor.run {
                    errorMessage = "An error occurred: \(error.localizedDescription)\n\nPlease try again or check your API key configuration."
                    showError = true
                    aiResub = false
                }
            }

            // Always clean up loading state unless we're retrying
            await MainActor.run {
                if !isRetrying {
                    isLoading = false
                } else {
                    // If this was a retry attempt that succeeded
                    isRetrying = false
                }
            }
        }
    }
}
