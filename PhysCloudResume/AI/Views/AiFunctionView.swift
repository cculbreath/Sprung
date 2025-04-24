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

    init(res: Binding<Resume?>) {
        _res = res

        let apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        openAIClient = OpenAIClientFactory.createClient(apiKey: apiKey)
        ttsProvider = OpenAITTSProvider(apiKey: apiKey)
    }

    var body: some View {
        if let myRes = res {
            AiCommsView(
                openAIClient: openAIClient,
                ttsProvider: ttsProvider,
                query: myRes.generateQuery(),
                res: $res,
                ttsEnabled: $ttsEnabled,
                ttsVoice: $ttsVoice
            )
            .onAppear { myRes.debounceExport() }
        } else {
            Text("No Resume Available")
        }
    }
}
