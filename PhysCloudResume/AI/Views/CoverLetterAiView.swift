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
    // MARK: - App Storage

    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"

    // MARK: - Bindings

    @Binding var buttons: CoverLetterButtons
    @Binding var refresh: Bool

    // Flag to determine if this is a new conversation or not
    private let isNewConversation: Bool

    // MARK: - Initialization

    init(buttons: Binding<CoverLetterButtons>, refresh: Binding<Bool>, isNewConversation: Bool = true) {
        _buttons = buttons
        _refresh = refresh
        self.isNewConversation = isNewConversation
    }

    // MARK: - Body

    var body: some View {
        // Create OpenAI client using our abstraction layer
        let openAIClient = OpenAIClientFactory.createClient(apiKey: openAiApiKey)

        // Initialize TTS provider
        let ttsProvider = OpenAITTSProvider(apiKey: openAiApiKey)

        // Initialize our main manager (renamed from CoverLetterController)
        CoverLetterAiManager(
            openAIClient: openAIClient,
            ttsProvider: ttsProvider,
            buttons: $buttons,
            refresh: $refresh,
            ttsEnabled: $ttsEnabled,
            ttsVoice: $ttsVoice,
            isNewConversation: isNewConversation
        )
        .onAppear { print("AI Cover Letter View") }
    }
}
