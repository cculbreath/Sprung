//
//  AiFunctionView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/9/24.
//  Updated by Christopher Culbreath on 5/20/25.
//

import SwiftUI

struct AiFunctionView: View {
    @Binding var res: Resume?
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"
    @AppStorage("openAiApiKey") var openAiKey: String = "none"
    
    // Add state for the query to handle asynchronous loading
    @State private var query: ResumeApiQuery?
    @State private var isLoadingQuery: Bool = false

    // Use our unified LLM client as a State property
    @State private var llmClient: AppLLMClientProtocol
    
    // For TTS functionality - using lazy initialization
    @State private var ttsProvider: OpenAITTSProvider?

    // Flag to determine if this is a new conversation or not
    private let isNewConversation: Bool
    
    // Access to AppState using Swift 6 conventions
    @Environment(\.appState) private var appState

    init(res: Binding<Resume?>, isNewConversation: Bool = false) {
        _res = res
        self.isNewConversation = isNewConversation
        
        if let resume = res.wrappedValue {
            // Clear any existing conversation context for new analysis
            Task { @MainActor in
                resume.clearConversationContext()
            }
        }

        // Initialize LLM client for chat
        _llmClient = State(initialValue: AppLLMClientFactory.createClient(
            for: AIModels.Provider.openai,
            appState: AppState()
        ))
        
        // TTS will be initialized in onAppear
    }
    
    // Load the query when the resume changes
    private func loadQuery() {
        guard let myRes = res, query == nil else { return }
        
        isLoadingQuery = true
        // Use the non-async version which now properly populates applicant data synchronously
        query = myRes.generateQuery()
        isLoadingQuery = false
    }

    var body: some View {
        Group {
            if res != nil {
                if let currentQuery = query {
                    AiCommsView(
                        client: llmClient,
                        query: currentQuery,
                        res: $res,
                        ttsEnabled: $ttsEnabled,
                        ttsVoice: $ttsVoice
                    )
                } else if isLoadingQuery {
                    ProgressView("Preparing...")
                        .frame(width: 100, height: 30)
                } else {
                    // This is a fallback that should rarely be seen
                    Button(action: { loadQuery() }) {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
            }
            else {
                Text("No Resume Available")
            }
        }
        .onAppear {
            // Properly initialize the client with AppState
            llmClient = AppLLMClientFactory.createClient(
                for: AIModels.Provider.openai,
                appState: appState
            )

            if let myRes = res {
                // Always export the resume when appearing
                myRes.debounceExport()
                // Load the query when appearing
                loadQuery()
            }
        }
        .onChange(of: res) { _, newRes in
            if newRes != nil {
                // Reset query when resume changes
                query = nil
                loadQuery()
            }
        }
    }
}
