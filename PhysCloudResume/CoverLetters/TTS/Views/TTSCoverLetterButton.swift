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

    /// Cover letter button states
    @Binding var buttons: CoverLetterButtons

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
        if ttsEnabled && cL.generated && !cL.content.isEmpty {
            Button(action: speakAction) {
                // Use different icon depending on playback state
                // Icon is filled when speaking or buffering, unfilled when paused or idle
                let iconFilled = isSpeaking || isBuffering
                let iconName = iconFilled ? "speaker.wave.3.fill" : "speaker.wave.3"

                ZStack {
                    // Non-animated icon
                    if !isBuffering {
                        Image(systemName: iconName)
                            .font(.system(size: 16, weight: .regular))
                            .frame(width: 28, height: 28)
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
            .disabled(buttons.runRequested || buttons.chooseBestRequested)
            .onChange(of: isBuffering) { _, newValue in
                print("TTSButton: buffering changed to \(newValue)")
            }
            .onChange(of: isSpeaking) { _, newValue in
                print("TTSButton: speaking changed to \(newValue)")
            }
            .onChange(of: isPaused) { _, newValue in
                print("TTSButton: paused changed to \(newValue)")
            }
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
