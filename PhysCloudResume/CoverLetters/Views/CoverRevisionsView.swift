//
//  CoverRevisionsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/16/24.
//

import SwiftUI

struct CoverRevisionsView: View {
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
    @Binding var buttons: CoverLetterButtons

    var body: some View {
        // Create client using our abstraction layer
        let openAIClient = OpenAIClientFactory.createClient(apiKey: openAiApiKey)

        RevisionsViewContent(
            openAIClient: openAIClient,
            buttons: $buttons
        )
        .onAppear { print("Ai Cover Letterv2") }
    }
}

struct RevisionsViewContent: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @State var tempMode: CoverLetterPrompts.EditorPrompts = .zissner
    @State var aiMode: CoverAiMode = .none
    @State private var customFeedback: String = ""
    @Binding var buttons: CoverLetterButtons
    let openAIClient: OpenAIClientProtocol

    // Use @Bindable for chatProvider
    @Bindable var chatProvider: CoverChatProvider

    init(
        openAIClient: OpenAIClientProtocol,
        buttons: Binding<CoverLetterButtons>
    ) {
        self.openAIClient = openAIClient
        _buttons = buttons
        chatProvider = CoverChatProvider(client: openAIClient)
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

        // Check if there's an existing cover letter for the current resume with `generated = false`
        if let existingLetter = jobAppStore.selectedApp?.coverLetters.first(where: { letter in
            !letter.generated
        }) {
            // Load the existing letter
            jobAppStore.selectedApp?.selectedCover = existingLetter
        } else {
            // No existing draft, create a new cover letter
            let oldContent = selectedCover.content // Unwrapped safely
            let newCL = coverLetterStore.createDuplicate(letter: selectedCover) // Unwrapped safely
            jobAppStore.selectedApp?.selectedCover = newCL // Assign new instance
            jobAppStore.selectedApp?.selectedCover?.currentMode = (tempMode == .custom) ? .revise : .rewrite
            jobAppStore.selectedApp?.selectedCover?.content = oldContent
            jobAppStore.selectedApp?.selectedCover?.editorPrompt = tempMode
        }

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
