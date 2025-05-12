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

/// Keeps a shared instance of the TTS provider to prevent recreation
@MainActor
final class TTSProviderManager {
    static let shared = TTSProviderManager()
    private var instance: OpenAITTSProvider?

    // Track whether TTS is currently needed
    private var ttsInitialized: Bool = false

    private init() {}

    func getProvider(apiKey: String) -> OpenAITTSProvider {
        if let provider = instance {
            return provider
        } else {
            let newProvider = OpenAITTSProvider(apiKey: apiKey)
            instance = newProvider
            return newProvider
        }
    }

    // New method to ensure TTS is only initialized when needed
    func getProviderIfNeeded(apiKey: String, ttsEnabled: Bool) -> OpenAITTSProvider? {
        if !ttsEnabled {
            // If TTS is disabled, we return nil and avoid initialization
            return nil
        }

        // Only initialize if TTS is enabled
        if !ttsInitialized {
            print("TTSProviderManager: Initializing TTS on first use")
            ttsInitialized = true
        }

        return getProvider(apiKey: apiKey)
    }
}

@MainActor
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

    // Keep client instance as a computed property to avoid body mutations
    private var openAIClient: OpenAIClientProtocol {
        OpenAIClientFactory.createClient(apiKey: openAiApiKey)
    }

    // Get shared TTS provider only if TTS is enabled
    private var ttsProvider: OpenAITTSProvider? {
        TTSProviderManager.shared.getProviderIfNeeded(apiKey: openAiApiKey, ttsEnabled: ttsEnabled)
    }

    // MARK: - Initialization

    init(buttons: Binding<CoverLetterButtons>, refresh: Binding<Bool>, isNewConversation: Bool = true) {
        _buttons = buttons
        _refresh = refresh
        self.isNewConversation = isNewConversation
    }

    // MARK: - Body

    var body: some View {
        // Initialize our main manager with optional TTS provider
        CoverLetterAiManager(
            openAIClient: openAIClient,
            ttsProvider: ttsProvider, // Now optional
            buttons: $buttons,
            refresh: $refresh,
            ttsEnabled: $ttsEnabled,
            ttsVoice: $ttsVoice,
            isNewConversation: isNewConversation
        )
        .onAppear {
            print("AI Cover Letter View appeared (TTS enabled: \(ttsEnabled))")
        }
    }
}
