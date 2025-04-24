//
//  CoverLetterAiView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/23/25.
//

import Foundation
import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Wrapper view for Cover Letter AI content. Initializes dependencies.
struct CoverLetterAiView: View {
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"
    @Binding var buttons: CoverLetterButtons
    @Binding var refresh: Bool

    var body: some View {
        // Create OpenAI client using our abstraction layer
        let openAIClient = OpenAIClientFactory.createClient(apiKey: openAiApiKey)

        // Initialize TTS provider
        let ttsProvider = OpenAITTSProvider(apiKey: openAiApiKey)

        CoverLetterAiContentView(
            openAIClient: openAIClient,
            ttsProvider: ttsProvider,
            buttons: $buttons,
            refresh: $refresh,
            ttsEnabled: $ttsEnabled,
            ttsVoice: $ttsVoice
        )
        .onAppear { print("Ai Cover Letter") }
    }
}
