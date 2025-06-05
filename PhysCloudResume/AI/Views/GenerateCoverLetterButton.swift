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
    let chatProvider: CoverChatProvider
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @State private var isProcessing = false

    var body: some View {
        if !isProcessing {
            Button {
                // Always create a new cover letter for every LLM request
                let newCL = coverLetterStore.createDuplicate(letter: cL)
                // Set the appropriate mode
                newCL.currentMode = .generate
                // Update the current letter reference
                cL = newCL
                isProcessing = true
                chatProvider.coverChatAction(
                    res: jobAppStore.selectedApp?.selectedRes,
                    jobAppStore: jobAppStore,
                    chatProvider: chatProvider,
                    isNewConversation: true // Explicitly start a new conversation
                )
                // Note: caller should reset isProcessing when done
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help("Generate new Cover Letter")
        } else {
            Image(systemName: "wand.and.rays")
                .font(.system(size: 18, weight: .regular))
                .frame(width: 32, height: 32)
                .symbolEffect(.variableColor.iterative.hideInactiveLayers.nonReversing)
        }
    }
}
