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
                if !cL.generated {
                    cL.currentMode = .generate
                } else {
                    let newCL = coverLetterStore.createDuplicate(letter: cL)
                    cL = newCL
                }
                chatProvider.coverChatAction(
                    res: jobAppStore.selectedApp?.selectedRes,
                    jobAppStore: jobAppStore,
                    chatProvider: chatProvider,
                    buttons: $buttons
                )
            } label: {
                Image("ai-squiggle")
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 28, height: 28)
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
