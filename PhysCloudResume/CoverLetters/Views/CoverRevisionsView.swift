//
//  CoverRevisionsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/16/24.
//

import SwiftUI

struct CoverRevisionsView: View {
    @Binding var buttons: CoverLetterButtons

    var body: some View {
        let client: AppLLMClientProtocol = AppLLMClientFactory.createClient(
            for: AIModels.Provider.openai,
            appState: AppState()
        )
        RevisionsViewContent(client: client, buttons: $buttons)
            .onAppear { Logger.debug("Ai Cover Letterv2") }
    }
}

struct RevisionsViewContent: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @State var tempMode: CoverLetterPrompts.EditorPrompts = .zissner
    @State private var customFeedback: String = ""
    @Binding var buttons: CoverLetterButtons
    let client: AppLLMClientProtocol

    // Use @Bindable for chatProvider
    @Bindable var chatProvider: CoverChatProvider

    init(
        client: AppLLMClientProtocol,
        buttons: Binding<CoverLetterButtons>
    ) {
        self.client = client
        _buttons = buttons
        chatProvider = CoverChatProvider(client: client)
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

            if !$buttons.wrappedValue.runRequested {
                Button((tempMode == .custom) ? "Revise" : "Rewrite") {
                    rewriteBut(
                        coverLetterStore: coverLetterStore,
                        jobAppStore: jobAppStore,
                        chatProvider: chatProvider,
                        buttons: $buttons,
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
        buttons: Binding<CoverLetterButtons>,
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
            buttons: buttons,
            customFeedback: customFeedback
        )
    }
}
