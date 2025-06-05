//
//  CoverRevisionsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/16/24.
//

import SwiftUI

/// Legacy view - may be unused
struct CoverRevisionsView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        RevisionsViewContent(appState: appState)
            .onAppear { Logger.debug("Ai Cover Letterv2") }
    }
}

struct RevisionsViewContent: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @State var tempMode: CoverLetterPrompts.EditorPrompts = .zissner
    @State private var customFeedback: String = ""
    let appState: AppState

    // Use @Bindable for chatProvider
    @Bindable var chatProvider: CoverChatProvider

    init(appState: AppState) {
        self.appState = appState
        chatProvider = CoverChatProvider(appState: appState)
    }

    var body: some View {
        VStack {
            Picker("", selection: $tempMode) {
                ForEach(CoverLetterPrompts.EditorPrompts.allCases, id: \.self) { status in

                    Text(String(describing: status).capitalized) // Using the enum case name instead of raw value
                        .tag(status)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            // Conditionally show the text input box
            if tempMode == .custom { // Assuming .custom is one of the enum cases
                TextField("Revision Feedback", text: $customFeedback) // Binding variable for text
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
            }

            if true { // Legacy button check removed
                Button((tempMode == .custom) ? "Revise" : "Rewrite") {
                    rewriteBut(
                        coverLetterStore: coverLetterStore,
                        jobAppStore: jobAppStore,
                        chatProvider: chatProvider,
                        customFeedback: $customFeedback
                    )
                }
            } else {
                ProgressView()
            }
        }
    }

    // Add a binding variable for the text field
    func rewriteBut(
        coverLetterStore: CoverLetterStore,
        jobAppStore: JobAppStore,
        chatProvider: CoverChatProvider,
        customFeedback: Binding<String>
    ) {
        guard let currentResume = jobAppStore.selectedApp?.selectedRes else {
            return
        }

        guard let selectedCover = jobAppStore.selectedApp?.selectedCover else {
            return
        }

        // Always create a new cover letter for revisions to maintain history
        let oldContent = selectedCover.content // Unwrapped safely
        let newCL = coverLetterStore.createDuplicate(letter: selectedCover) // Creates with next available option letter

        // Set up the new cover letter for revision
        newCL.currentMode = (tempMode == .custom) ? .revise : .rewrite
        newCL.content = oldContent
        newCL.editorPrompt = tempMode
        newCL.generated = false // Mark as ungenerated until we get the AI response

        // Select the new cover letter
        jobAppStore.selectedApp?.selectedCover = newCL

        // Perform the revision or rewrite operation
        chatProvider.coverChatRevise(
            res: currentResume, // Already safely unwrapped earlier
            jobAppStore: jobAppStore,
            chatProvider: chatProvider,
            customFeedback: customFeedback
        )
    }
}
