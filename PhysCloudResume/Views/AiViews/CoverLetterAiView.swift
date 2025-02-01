//
//  CoverLetterAiView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/12/24.
//

import Foundation
import SwiftOpenAI
import SwiftUI

struct CoverLetterAiView: View {
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
    @Binding var buttons: CoverLetterButtons
    @Binding var refresh: Bool

    var body: some View {
        CoverLetterAiContentView(
            service: OpenAIServiceFactory.service(
                apiKey: openAiApiKey, debugEnabled: false
            ),
            buttons: $buttons, refresh: $refresh
        )
        .onAppear { print("Ai Cover Letter") }
    }
}

struct CoverLetterAiContentView: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    @State var aiMode: CoverAiMode = .none
    @Binding var buttons: CoverLetterButtons
    @Binding var refresh: Bool
    let service: OpenAIService

    // Use @Bindable for chatProvider
    @Bindable var chatProvider: CoverChatProvider

    init(
        service: OpenAIService,
        buttons: Binding<CoverLetterButtons>,
        refresh: Binding<Bool>
    ) {
        self.service = service
        _buttons = buttons
        chatProvider = CoverChatProvider(service: service)
        _refresh = refresh
    }

    var body: some View {
        if jobAppStore.selectedApp?.selectedCover != nil {
            @Bindable var cL = jobAppStore.selectedApp!.selectedCover!

            HStack(spacing: 4) {
                VStack {
                    if !$buttons.wrappedValue.runRequested {
                        Button(action: {
                            print("Not loading")
                            if !cL.generated {
                                cL.currentMode = .generate
                            } else {
                                @Bindable var newCL = coverLetterStore.createDuplicate(letter: cL)
                                cL = newCL // Assign new instance
                                print("new cover letter")
                            }

                            chatProvider.coverChatAction(res: jobAppStore.selectedApp?.selectedRes,
                                                         jobAppStore: jobAppStore,
                                                         chatProvider: chatProvider,
                                                         buttons: $buttons)
                        }) {
                            Image("ai-squiggle")
                                .font(.system(size: 20, weight: .regular))
                        }
                        .help("Generate new Cover Letter")
                    } else {
                        ProgressView()
                            .scaleEffect(0.75, anchor: .center)
                    }
                }
            }

//      .onChange(of: buttons.runRequested) { oldValue, newValue in
//        if newValue {
//          chatAction(res: jobAppStore.selectedApp?.selectedRes)
//        }
        } else {
            EmptyView()
        }
    }
}
