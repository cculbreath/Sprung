//
//  TTSCoverLetterButton.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/23/25.
//

import SwiftUI

/// Button for text-to-speech playback of the cover letter.
struct TTSCoverLetterButton: View {
    // MARK: - Properties

    /// The cover letter to speak
    @Binding var cL: CoverLetter

    /// Whether TTS is enabled in user settings
    @Binding var ttsEnabled: Bool

    /// The selected voice in user settings
    @Binding var ttsVoice: String

    /// Whether speech is currently playing
    @Binding var isSpeaking: Bool

    /// Whether speech is currently paused
    @Binding var isPaused: Bool

    /// Whether speech is currently buffering
    @Binding var isBuffering: Bool

    /// Action to perform when the button is clicked
    let speakAction: () -> Void

    // MARK: - Body

    var body: some View {
        // Debug: Print the conditions for showing the button
//        let _ = Logger.debug("[TTSCoverLetterButton] Evaluating conditions: ttsEnabled=\(ttsEnabled), cL.generated=\(cL.generated), !cL.content.isEmpty=\(!cL.content.isEmpty)")
        // Debug: Print current playback state when the button view is built
//        let _ = Logger.debug("[TTSCoverLetterButton] Current playback state: isSpeaking=\(isSpeaking), isPaused=\(isPaused), isBuffering=\(isBuffering)")

        if ttsEnabled && cL.generated && !cL.content.isEmpty {
            Button(action: {
                // Debug: Print when the action is triggered
//                Logger.debug("[TTSCoverLetterButton] SpeakAction TRIGGERED. Current state: isSpeaking=\(isSpeaking), isPaused=\(isPaused), isBuffering=\(isBuffering)")
                speakAction()
            }) {
                // Use different icon depending on playback state
                // Icon is filled when speaking or buffering, unfilled when paused or idle
                let iconFilled = isSpeaking || isBuffering
                let iconName = iconFilled ? "speaker.wave.3.fill" : "speaker.wave.3"

                ZStack {
                    // Non-animated icon
                    if !isBuffering {
                        Image(systemName: iconName)
                            .font(.system(size: 18, weight: .regular))
                            .frame(width: 32, height: 32)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(buttonColor)
                    }

                    // Animated icon shown only when buffering
                    if isBuffering {
                        Image(systemName: iconName)
                            .font(.system(size: 16, weight: .regular))
                            .frame(width: 28, height: 28)
                            .symbolRenderingMode(.monochrome)
                            .symbolEffect(.bounce, options: .repeating)
                            .foregroundStyle(.orange) // Force orange during buffering
                    }
                }
            }
            .buttonStyle(.plain)
            .help(helpText)
            .disabled(false) // Note: Legacy button state removed
            .onChange(of: isBuffering) { _, newValue in
//                Logger.debug("[TTSCoverLetterButton] Buffering state changed to \(newValue)")
            }
            .onChange(of: isSpeaking) { _, newValue in
//                Logger.debug("[TTSCoverLetterButton] Speaking state changed to \(newValue)")
            }
            .onChange(of: isPaused) { _, newValue in
//                Logger.debug("[TTSCoverLetterButton] Paused state changed to \(newValue)")
            }
        } else {
            // Debug: Print why the button is not shown
//            let _ = Logger.debug("[TTSCoverLetterButton] Button NOT shown. Reasons: ttsEnabled=\(ttsEnabled), cL.generated=\(cL.generated), cL.content.isEmpty=\(cL.content.isEmpty)")
            // Return an EmptyView or a disabled button if you want a placeholder
            // For now, it will simply not render if conditions aren't met.
        }
    }

    // MARK: - Helper Properties

    /// The color of the button based on its state
    private var buttonColor: Color {
        if isBuffering {
            return .orange
        } else if isSpeaking || isPaused {
            return .accentColor
        } else {
            return .primary
        }
    }

    /// Help text for the button based on its state
    private var helpText: String {
        if isBuffering { return "Cancel" }
        if isSpeaking { return "Pause playback" }
        if isPaused { return "Resume playback" }
        return "Read cover letter aloud"
    }
}
