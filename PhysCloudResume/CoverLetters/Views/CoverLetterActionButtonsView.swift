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

    /// Provider for chat-based cover letter generation
    let chatProvider: CoverChatProvider

    /// Action to perform when choosing the best cover letter
    let chooseBestAction: () -> Void
    
    /// Action to perform when choosing with multiple models
    let multiModelChooseBestAction: () -> Void

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
            HStack(spacing: 16) {
                // Button to generate a new cover letter
                GenerateCoverLetterButton(
                    cL: $coverLetter,
                    chatProvider: chatProvider
                )

                // Button to select the best cover letter
                ChooseBestCoverLetterButton(
                    cL: $coverLetter,
                    action: chooseBestAction,
                    multiModelAction: multiModelChooseBestAction
                )

                // Button for text-to-speech functionality
                TTSCoverLetterButton(
                    cL: $coverLetter,
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

/// Preview provider for SwiftUI canvas
