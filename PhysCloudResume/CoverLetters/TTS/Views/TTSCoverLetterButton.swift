//
//  TTSCoverLetterButton.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/23/25.
//

import SwiftUI

/// Button for text-to-speech playback of the cover letter.
struct TTSCoverLetterButton: View {
    @Binding var cL: CoverLetter
    @Binding var buttons: CoverLetterButtons
    @Binding var ttsEnabled: Bool
    @Binding var ttsVoice: String
    @Binding var isSpeaking: Bool
    @Binding var isPaused: Bool
    @Binding var isBuffering: Bool
    let speakAction: () -> Void

    var body: some View {
        if ttsEnabled && cL.generated && !cL.content.isEmpty {
            Button(action: speakAction) {
                let iconFilled = isSpeaking || isBuffering
                let iconName = iconFilled ? "speaker.wave.3.fill" : "speaker.wave.3"
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 36, height: 36)
                    .symbolRenderingMode(.monochrome)
                    .symbolEffect(.pulse, value: isBuffering)
                    .foregroundColor(
                        isBuffering
                            ? .orange
                            : (isSpeaking || isPaused)
                            ? .accentColor
                            : .primary
                    )
            }
            .buttonStyle(.plain)
            .help(helpText)
            .disabled(buttons.runRequested || buttons.chooseBestRequested)
        }
    }

    private var helpText: String {
        if isBuffering { return "Cancel" }
        if isSpeaking { return "Pause playback" }
        if isPaused { return "Resume playback" }
        return "Read cover letter aloud"
    }
}
