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
    @AppStorage("ttsInstructions") private var ttsInstructions: String = ""
    @State private var isSpeaking: Bool = false
    @State private var ttsError: String? = nil
    @State private var showTTSError: Bool = false

    // Store references to clients for AI operations
    private let openAIClient: OpenAIClientProtocol
    private let ttsProvider: OpenAITTSProvider

    init(
        openAIClient: OpenAIClientProtocol,
        ttsProvider: OpenAITTSProvider,
        query: ResumeApiQuery,
        res: Binding<Resume?>,
        ttsEnabled: Binding<Bool> = .constant(false),
        ttsVoice: Binding<String> = .constant("nova")
    ) {
        // Initialize with abstraction layer client
        _chatProvider = State(initialValue: ResumeChatProvider(client: openAIClient))
        self.openAIClient = openAIClient
        self.ttsProvider = ttsProvider
        _q = State(initialValue: query)
        _myRes = res
        _ttsEnabled = ttsEnabled
        _ttsVoice = ttsVoice
    }

    var body: some View {
        execQuery
            .sheet(isPresented: $sheetOn) {
                print("sheet dismissed")
            } content: {
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
                sheetOn = true
                revisions = validateRevs(res: myRes, revs: newValue) ?? [] // Updated this call
                currentRevNode = revisions[0]
                if currentRevNode != nil {
                    currentFeedbackNode = FeedbackNode(
                        id: currentRevNode!.id,
                        originalValue: currentRevNode!.oldValue,
                        proposedRevision: currentRevNode!.newValue,
                        actionRequested: .unevaluated,
                        reviewerComments: "",
                        isTitleNode: currentRevNode!.isTitleNode
                    )
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
                            print("Request timeout triggered in AiCommsView")

                            // If this is the first attempt, retry once
                            if retryCount == 0 {
                                print("Retrying AI request after timeout")
                                retryCount += 1
                                isRetrying = true

                                // Retry the request
                                chatAction(hasRevisions: true)

                                // Set another timeout for the retry
                                DispatchQueue.main.asyncAfter(deadline: .now() + 180) { // 3 minutes for retry
                                    if isLoading && aiResub {
                                        print("Retry request timeout triggered - dismissing UI")
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
                            print("Notloading")
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

            // TTS controls - only show when TTS is enabled in settings
            if ttsEnabled && !revisions.isEmpty {
                Button(action: {
                    speakRevisions()
                }) {
                    Label {
                        Text(isSpeaking ? "Stop" : "Speak")
                            .font(.caption)
                    } icon: {
                        Image(systemName: isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                            .font(.system(size: 16))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isLoading)
                .help(isSpeaking ? "Stop speaking" : "Speak revision suggestions")
            }
        }
        .padding(.horizontal)
        .alert("TTS Error", isPresented: $showTTSError) {
            Button("OK") { showTTSError = false }
        } message: {
            Text(ttsError ?? "An error occurred with text-to-speech")
        }
    }

    // Validation function for revisions
    func validateRevs(res: Resume?, revs: [ProposedRevisionNode]) -> [ProposedRevisionNode]? {
        print("Validating revisions...")
        var validRevs = revs
        if let myRes = res {
            let updateNodes = myRes.getUpdatableNodes()

            for (index, item) in validRevs.enumerated() {
                // Check by ID first
                if let matchedNode = updateNodes.first(where: { $0["id"] as? String == item.id }) {
                    print("\(item.id) found")
                    continue
                } else if let matchedByValue = updateNodes.first(where: { $0["value"] as? String == item.oldValue }), let id = matchedByValue["id"] as? String {
                    // Update revision's ID if matched by value
                    validRevs[index].id = id

                    // Make sure to preserve isTitleNode when matching by value
                    validRevs[index].isTitleNode = matchedByValue["isTitleNode"] as? Bool ?? false

                    print("\(item.id) updated to use ID from matched node. isTitleNode: \(validRevs[index].isTitleNode)")

                } else {
                    print("No match found for revision: \(item.id) - \(item.oldValue)")
                }
            }
            return validRevs
        }
        return nil
    }

    /// Uses TTS to speak the AI revision suggestions
    func speakRevisions() {
        // If currently speaking, stop playback
        if isSpeaking {
            // Tell the TTS provider to stop playback
            isSpeaking = false
            return
        }

        // Make sure we have revisions to speak
        guard !revisions.isEmpty else {
            return
        }

        // Format the revisions into a readable script
        var speechText = "Here are my suggested revisions for your résumé:\n\n"

        for (index, revision) in revisions.enumerated() {
            // For title nodes, provide context about the section
            if revision.isTitleNode {
                speechText += "For the section \(revision.oldValue.trimmingCharacters(in: .whitespacesAndNewlines)), "
                speechText += "I suggest changing it to \(revision.newValue.trimmingCharacters(in: .whitespacesAndNewlines)).\n\n"
            } else {
                speechText += "Revision \(index + 1): "
                speechText += "I suggest changing \"\(revision.oldValue.trimmingCharacters(in: .whitespacesAndNewlines))\" "
                speechText += "to \"\(revision.newValue.trimmingCharacters(in: .whitespacesAndNewlines))\".\n\n"
            }

            // Add the reasoning if available
            if !revision.why.isEmpty {
                speechText += "Here's why: \(revision.why)\n\n"
            }
        }

        // Set UI state to speaking
        isSpeaking = true

        // Get selected voice (default to nova if not valid)
        let voice = OpenAITTSProvider.Voice(rawValue: ttsVoice) ?? .nova

        // Get voice instructions if available
        let instructions = ttsInstructions.isEmpty ? nil : ttsInstructions

        // Request TTS conversion and playback with instructions
        ttsProvider.speakText(speechText, voice: voice, instructions: instructions) { error in
            // Update UI state when speech completes or errors
            DispatchQueue.main.async {
                isSpeaking = false

                if let error = error {
                    ttsError = "Text-to-speech error: \(error.localizedDescription)"
                    showTTSError = true
                }
            }
        }
    }

    func chatAction(hasRevisions: Bool = false) {
        if let jobApp = jobAppStore.selectedApp {
            jobApp.status = .inProgress
        }

        Task {
            print("chatAction starting")
            isLoading = true

            do {
                // Prepare messages for API call using our abstraction layer
                if !hasRevisions {
                    // Set up system and user messages for initial query
                    chatProvider.genericMessages = [
                        q.genericSystemMessage,
                        ChatMessage(role: .user, content: q.wholeResumeQueryString)
                    ]
                } else {
                    // Add revision feedback prompt to existing message history
                    chatProvider.genericMessages.append(
                        ChatMessage(role: .user, content: q.revisionPrompt(fbnodes))
                    )
                }

                // Get the model string
                let modelString = OpenAIModelFetcher.getPreferredModelString()
                print("Using OpenAI model for resume query: \(modelString)")

                // Set up a timeout task that will run if the main task takes too long
                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds - just for checking if progress is made
                    if isLoading && !Task.isCancelled {
                        print("AI operation in progress...")
                    }
                }

                // Execute the API call with our abstraction layer
                try await chatProvider.startChat(messages: chatProvider.genericMessages)

                // Cancel the timeout task since we completed successfully
                timeoutTask.cancel()

                // Check for error messages from the chat provider
                if !chatProvider.errorMessage.isEmpty {
                    throw NSError(domain: "OpenAIError",
                                  code: 1001,
                                  userInfo: [NSLocalizedDescriptionKey: chatProvider.errorMessage])
                }
            } catch {
                print("Error in chatAction: \(error.localizedDescription)")

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
