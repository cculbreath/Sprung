//
//  GenerateCoverLetterButton.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/23/25.
//

import SwiftUI

/// Button for generating or regenerating a cover letter via AI.
struct GenerateCoverLetterButton: View {
    @Binding var cL: CoverLetter
    @Binding var buttons: CoverLetterButtons
    let chatProvider: CoverChatProvider
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    var body: some View {
        if !buttons.runRequested {
            Button {
                // Always create a new cover letter for every LLM request
                let newCL = coverLetterStore.createDuplicate(letter: cL)
                // Set the appropriate mode
                newCL.currentMode = .generate
                // Update the current letter reference
                cL = newCL
                chatProvider.coverChatAction(
                    res: jobAppStore.selectedApp?.selectedRes,
                    jobAppStore: jobAppStore,
                    chatProvider: chatProvider,
                    buttons: $buttons,
                    isNewConversation: true // Explicitly start a new conversation
                )
            } label: {
                Image("ai-squiggle")
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help("Generate new Cover Letter")
        } else {
            ProgressView()
                .scaleEffect(0.75, anchor: .center)
                .frame(width: 28, height: 28)
        }
    }
}
