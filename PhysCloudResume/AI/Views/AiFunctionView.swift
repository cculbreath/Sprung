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
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"

    // Use our abstraction layer for OpenAI. Fetch the key directly from
    // UserDefaults instead of relying on the `@AppStorage` property wrapper in
    // order to avoid the mutating‑getter compile error.
    private let openAIClient: OpenAIClientProtocol

    // For TTS functionality
    private let ttsProvider: OpenAITTSProvider

    // Flag to determine if this is a new conversation or not
    private let isNewConversation: Bool

    init(res: Binding<Resume?>, isNewConversation: Bool = false) {
        _res = res
        self.isNewConversation = isNewConversation

        let apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        openAIClient = OpenAIClientFactory.createClient(apiKey: apiKey)
        ttsProvider = OpenAITTSProvider(apiKey: apiKey)

        // If this is a new conversation, clear the previousResponseId during initialization
        if isNewConversation, let resume = res.wrappedValue {
            resume.previousResponseId = nil
        }
    }

    var body: some View {
        Group {
            if let myRes = res {
                AiCommsView(
                    openAIClient: openAIClient,
                    ttsProvider: ttsProvider,
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
