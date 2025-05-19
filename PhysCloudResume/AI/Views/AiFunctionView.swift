//
//  AiFunctionView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/9/24.
//

import SwiftUI

struct AiFunctionView: View {
    @Binding var res: Resume?
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"
    
    // Add state for the query to handle asynchronous loading
    @State private var query: ResumeApiQuery?
    @State private var isLoadingQuery: Bool = false

    // Use our abstraction layer for LLM clients. Fetch the keys directly from
    // UserDefaults instead of relying on the `@AppStorage` property wrapper in
    // order to avoid the mutating‑getter compile error.
    private let llmClient: OpenAIClientProtocol

    // For TTS functionality
    private let ttsProvider: OpenAITTSProvider

    // Flag to determine if this is a new conversation or not
    private let isNewConversation: Bool

    init(res: Binding<Resume?>, isNewConversation _: Bool = false) {
        _res = res
        isNewConversation = false // resume convo shouldn't be resumed. Prompts don't expect context
        if let resume = res.wrappedValue {
            resume.previousResponseId = nil // resume convo shouldn't be resumed. Prompts don't expect context
        }

        // Get API keys from UserDefaults
        let openAiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        
        // Create the appropriate client
        llmClient = OpenAIClientFactory.createClient(apiKey: openAiKey)
        
        // TTS is still using OpenAI
        ttsProvider = OpenAITTSProvider(apiKey: openAiKey)
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
                        openAIClient: llmClient,
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
                
                // Add actions for when view appears
                // Using onChange instead of onAppear to ensure the query is refreshed when res changes
                // We can't use Task inside the view because it would cause a state update during view update
            }
            else {
                Text("No Resume Available")
            }
        }
        .onAppear {
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
