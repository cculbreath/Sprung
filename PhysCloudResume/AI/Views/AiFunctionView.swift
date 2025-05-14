//
//  AiFunctionView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/9/24.
//

import SwiftUI

struct AiFunctionView: View {
    @Binding var res: Resume?
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
    @AppStorage("geminiApiKey") var geminiApiKey: String = "none"
    @AppStorage("preferredLLMModel") var preferredLLMModel: String = AIModels.gpt4o
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"

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
        let geminiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? "none"
        let modelName = UserDefaults.standard.string(forKey: "preferredLLMModel") ?? AIModels.gpt4o
        
        // Create the appropriate client based on the selected model
        llmClient = OpenAIClientFactory.createClientForModel(
            openAiApiKey: openAiKey, 
            geminiApiKey: geminiKey, 
            modelName: modelName
        )
        
        // TTS is still using OpenAI
        ttsProvider = OpenAITTSProvider(apiKey: openAiKey)
    }

    var body: some View {
        Group {
            if let myRes = res {
                AiCommsView(
                    openAIClient: llmClient,
                    query: myRes.generateQuery(),
                    res: $res,
                    ttsEnabled: $ttsEnabled,
                    ttsVoice: $ttsVoice
                )
                .onAppear {
                    // Always export the resume when appearing
                    myRes.debounceExport()
                }
            } else {
                Text("No Resume Available")
            }
        }
    }
}
