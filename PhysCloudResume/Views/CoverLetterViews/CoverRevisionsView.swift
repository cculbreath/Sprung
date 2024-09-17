//
//  RevisionsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/14/24.
//

import SwiftOpenAI
import SwiftUI

struct CoverRevisionsView: View {
  @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
  @Binding var buttons: CoverLetterButtons

  var body: some View {

    RevisionsViewContent(
      service: OpenAIServiceFactory.service(
        apiKey: openAiApiKey, debugEnabled: false),
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
  @State var isLoading = false
  @Binding var buttons: CoverLetterButtons
  let service: OpenAIService

  // Use @Bindable for chatProvider
  @Bindable var chatProvider: CoverChatProvider

  init(
    service: OpenAIService,
    buttons: Binding<CoverLetterButtons>
  ) {
    self.service = service
    self._buttons = buttons
    self.chatProvider = CoverChatProvider(service: service)
  }

  var body: some View {
    Picker("", selection: $tempMode) {
      ForEach(CoverLetterPrompts.EditorPrompts.allCases, id: \.self) { status in
        Text(String(describing: status))  // Using the enum case name instead of raw value
          .tag(status)
      }
    }
    .pickerStyle(SegmentedPickerStyle())
    if !isLoading {
      Button("Rewrite") {
        rewriteBut(
          coverLetterStore: coverLetterStore,
          jobAppStore: jobAppStore,
          chatProvider: chatProvider,
          isLoading: $isLoading,
          buttons: $buttons
        )
      }
    } else {
      ProgressView()
    }
  }
  func rewriteBut(
    coverLetterStore: CoverLetterStore,
    jobAppStore: JobAppStore,
    chatProvider: CoverChatProvider,
    isLoading: Binding<Bool>,
    buttons: Binding<CoverLetterButtons>
  ) {
    let oldContent = jobAppStore.selectedApp!.selectedCover!.content
    var newCL = coverLetterStore.create(jobApp: jobAppStore.selectedApp!)
    jobAppStore.selectedApp!.selectedCover = newCL  // Assign new instance\
    jobAppStore.selectedApp!.selectedCover!.currentMode = .rewrite
    jobAppStore.selectedApp!.selectedCover!.content = oldContent
    jobAppStore.selectedApp!.selectedCover!.editorPrompt = tempMode
    print("new cover letter")
    chatProvider.coverChatAction(
      res: jobAppStore.selectedApp!.selectedRes,
      jobAppStore: jobAppStore,
      isLoading: isLoading,
      chatProvider: chatProvider,
      buttons: buttons
    )
  }
}
