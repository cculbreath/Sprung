//
//  CoverLetterActionButtonsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//


//
//  CoverLetterActionButtonsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import SwiftUI

/// A view that displays action buttons for cover letter operations
struct CoverLetterActionButtonsView: View {
    // MARK: - Properties
    
    /// The cover letter being operated on
    @Binding var coverLetter: CoverLetter
    
    /// Button states for the cover letter actions
    @Binding var buttons: CoverLetterButtons
    
    /// Provider for chat-based cover letter generation
    let chatProvider: CoverChatProvider
    
    /// Action to perform when choosing the best cover letter
    let chooseBestAction: () -> Void
    
    /// Action to perform when activating speech
    let speakAction: () -> Void
    
    // MARK: - TTS-related properties
    
    /// Whether text-to-speech is enabled
    @Binding var ttsEnabled: Bool
    
    /// The voice to use for text-to-speech
    @Binding var ttsVoice: String
    
    /// Whether speech is currently playing
    @Binding var isSpeaking: Bool
    
    /// Whether speech is currently paused
    @Binding var isPaused: Bool
    
    /// Whether speech is currently buffering
    @Binding var isBuffering: Bool
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if coverLetter.id != nil {
                HStack(spacing: 16) {
                    // Button to generate a new cover letter
                    GenerateCoverLetterButton(
                        cL: $coverLetter,
                        buttons: $buttons,
                        chatProvider: chatProvider
                    )
                    
                    // Button to select the best cover letter
                    ChooseBestCoverLetterButton(
                        cL: $coverLetter,
                        buttons: $buttons, 
                        action: chooseBestAction
                    )
                    
                    // Button for text-to-speech functionality
                    TTSCoverLetterButton(
                        cL: $coverLetter,
                        buttons: $buttons,
                        ttsEnabled: $ttsEnabled,
                        ttsVoice: $ttsVoice,
                        isSpeaking: $isSpeaking,
                        isPaused: $isPaused,
                        isBuffering: $isBuffering,
                        speakAction: speakAction
                    )
                }
            }
        }
    }
}

/// Preview provider for SwiftUI canvas
struct CoverLetterActionButtonsView_Previews: PreviewProvider {
    static var previews: some View {
        // This is a simplified preview - you would need to provide mocked values
        // for a complete preview to work
        CoverLetterActionButtonsView(
            coverLetter: .constant(CoverLetter()),
            buttons: .constant(CoverLetterButtons()),
            chatProvider: CoverChatProvider(client: MockOpenAIClient()),
            chooseBestAction: {},
            speakAction: {},
            ttsEnabled: .constant(true),
            ttsVoice: .constant("nova"),
            isSpeaking: .constant(false),
            isPaused: .constant(false),
            isBuffering: .constant(false)
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}

/// Mock OpenAI client for previews
private class MockOpenAIClient: OpenAIClientProtocol {
    func sendTTSRequest(text: String, voice: String, instructions: String?, onComplete: @escaping (Result<Data, Error>) -> Void) {
        // Mock implementation
    }
    
    func sendTTSStreamingRequest(text: String, voice: String, instructions: String?, onChunk: @escaping (Result<Data, Error>) -> Void, onComplete: @escaping (Error?) -> Void) {
        // Mock implementation
    }
    
    func sendChatRequest(messages: [AIMessage], temperature: Double, systemPrompt: String?, onComplete: @escaping (Result<AIMessage, Error>) -> Void) {
        // Mock implementation
    }
    
    func sendChatStreamingRequest(messages: [AIMessage], temperature: Double, systemPrompt: String?, onChunk: @escaping (Result<AIStreamingChunk, Error>) -> Void, onComplete: @escaping (Error?) -> Void) {
        // Mock implementation
    }
}