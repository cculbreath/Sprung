//
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
    @AppStorage("ttsInstructions") private var ttsInstructions: String = ""
    @State private var ttsError: String? = nil
    @State private var showTTSError: Bool = false

    // Read‑aloud playback state
    private enum ReadAloudState {
        case idle
        case buffering
        case playing
        case paused
    }

    @State private var readAloudState: ReadAloudState = .idle

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

            if ttsEnabled && !revisions.isEmpty && false {
                Button(action: {
                    // Detect ⌥‑click to force a fresh TTS request
                    let optionPressed = NSEvent.modifierFlags.contains(.option)
                    readAloudButtonTapped(optionPressed: optionPressed)
                }) {
                    Image(systemName: readAloudIconName)
                        .font(.system(size: 16))
                        // Pulsing yellow while buffering
                        .symbolEffect(.pulse, options: .repeating, value: readAloudState == .buffering)
                        .foregroundColor(readAloudIconColor)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isLoading)
                .help(readAloudHelpText)
            }
        }
        .padding(.horizontal)
        .alert("TTS Error", isPresented: $showTTSError) {
            Button("OK") { showTTSError = false }
        } message: {
            Text(ttsError ?? "An error occurred with text-to-speech")
        }
    }

    // MARK: ‑ Read‑Aloud Helpers

    /// Write a read‑aloud debug line and flush stdout so it appears immediately.
    private func log(_: String) {
        fflush(stdout)
    }

    private var readAloudIconName: String {
        switch readAloudState {
        case .buffering, .playing:
            return "speaker.wave.3.fill"
        case .paused, .idle:
            return "speaker.wave.3"
        }
    }

    private var readAloudIconColor: Color {
        switch readAloudState {
        case .buffering:
            return .yellow
        case .playing, .paused:
            return .blue
        case .idle:
            return .primary
        }
    }

    private var readAloudHelpText: String {
        switch readAloudState {
        case .buffering:
            return "Buffering…"
        case .playing:
            return "Pause playback"
        case .paused:
            return "Resume playback"
        case .idle:
            return "Read aloud"
        }
    }

    private func readAloudButtonTapped(optionPressed: Bool) {
        log("Button tapped. optionPressed: \(optionPressed), state: \(readAloudState)")
        // Option‑click always stops playback completely
        if optionPressed {
            log("option click -> stopPlayback")
            stopPlayback()
            return
        }

        // Handle state transitions
        switch readAloudState {
        case .buffering:
            log("tap ignored during buffering")
            return
        case .idle:
            log("idle -> startPlayback")
            startPlayback()
        case .playing:
            log("playing -> pausePlayback")
            pausePlayback()
        case .paused:
            log("paused -> resumePlayback")
            resumePlayback()
        }
    }

    private func startPlayback() {
        guard !revisions.isEmpty else {
            log("startPlayback aborted: no revisions")
            return
        }
        log("startPlayback -> buffering")
        readAloudState = .buffering
        speakRevisions() // will flip to playing once audio starts
    }

    private func pausePlayback() {
        log("pausePlayback requested")
        if ttsProvider.pause() {
            log("pausePlayback succeeded -> paused")
            readAloudState = .paused
        } else {
            log("pausePlayback FAILED")
        }
    }

    private func resumePlayback() {
        log("resumePlayback requested")
        if ttsProvider.resume() {
            log("resumePlayback succeeded -> playing")
            readAloudState = .playing
        } else {
            log("resumePlayback FAILED")
        }
    }

    private func stopPlayback() {
        log("stopPlayback invoked -> idle")
        ttsProvider.stopSpeaking()
        readAloudState = .idle
    }

    // Validation function for revisions
    func validateRevs(res: Resume?, revs: [ProposedRevisionNode]) -> [ProposedRevisionNode]? {
        var validRevs = revs
        if let myRes = res {
            let updateNodes = myRes.getUpdatableNodes()

            for (index, item) in validRevs.enumerated() {
                // Check by ID first
                if let matchedNode = updateNodes.first(where: { $0["id"] as? String == item.id }) {
                    continue
                } else if let matchedByValue = updateNodes.first(where: { $0["value"] as? String == item.oldValue }), let id = matchedByValue["id"] as? String {
                    // Update revision's ID if matched by value
                    validRevs[index].id = id

                    // Make sure to preserve isTitleNode when matching by value
                    validRevs[index].isTitleNode = matchedByValue["isTitleNode"] as? Bool ?? false

                } else {}
            }
            return validRevs
        }
        return nil
    }

    /// Uses TTS to speak the AI revision suggestions
    func speakRevisions() {
        log("speakRevisions called; requesting TTS for revisions")
        // Make sure we have revisions to speak
        guard !revisions.isEmpty else {
            return
        }
        // Buffering state set by startPlayback

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

        // Set up buffering state handler
        ttsProvider.onBufferingStateChanged = { buffering in
            DispatchQueue.main.async {
                log("onBufferingStateChanged -> \(buffering)")
                // Only update UI state if we're currently in a compatible state
                if buffering && self.readAloudState == .buffering {
                    // Keep it in buffering state
                } else if buffering && self.readAloudState == .idle {
                    self.readAloudState = .buffering
                }
            }
        }

        // Callbacks to manage state transitions
        ttsProvider.onReady = {
            DispatchQueue.main.async {
                log("onReady -> playing")
                self.readAloudState = .playing
            }
        }

        ttsProvider.onFinish = {
            DispatchQueue.main.async {
                log("onFinish -> idle")
                self.readAloudState = .idle
            }
        }

        // Get selected voice (default to nova if not valid)
        let voice = OpenAITTSProvider.Voice(rawValue: ttsVoice) ?? .nova

        // Get voice instructions if available
        let instructions = ttsInstructions.isEmpty ? nil : ttsInstructions

        // Request streaming TTS playback with instructions
        ttsProvider.streamAndPlayText(speechText, voice: voice, instructions: instructions) { error in
            DispatchQueue.main.async {
                if let error = error {
                    log("speakText completion error: \(error.localizedDescription)")
                    self.ttsError = "Text-to-speech error: \(error.localizedDescription)"
                    self.showTTSError = true
                    self.readAloudState = .idle
                }
            }
        }
    }

    func chatAction(hasRevisions: Bool = false) {
        if let jobApp = jobAppStore.selectedApp {
            jobApp.status = .inProgress
        }

        Task {
            isLoading = true

            do {
                // Prepare messages for API call using our abstraction layer
                if !hasRevisions {
                    // Set up system and user messages for initial query
                    chatProvider.genericMessages = [
                        q.genericSystemMessage,
                        ChatMessage(role: .user, content: q.wholeResumeQueryString),
                    ]
                } else {
                    // Add revision feedback prompt to existing message history
                    chatProvider.genericMessages.append(
                        ChatMessage(role: .user, content: q.revisionPrompt(fbnodes))
                    )
                }

                // Get the model string
                let modelString = OpenAIModelFetcher.getPreferredModelString()

                // Set up a timeout task that will run if the main task takes too long
                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds - just for checking if progress is made
                    if isLoading && !Task.isCancelled {}
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
