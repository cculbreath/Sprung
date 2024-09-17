//
//  CoverLetterAi.swift
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

  var body: some View {

    CoverLetterAiContentView(
      service: OpenAIServiceFactory.service(
        apiKey: openAiApiKey, debugEnabled: false),
      buttons: $buttons
    )
    .onAppear { print("Ai Cover Letter") }

  }
}

struct CoverLetterAiContentView: View {
  @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

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
    if let cL = jobAppStore.selectedApp?.selectedCover {
      HStack(spacing: 4) {
        VStack {
          if !isLoading {
            Button(action: {
              print("Not loading")
              if !cL.generated {
                cL.currentMode = .generate
              } else {
                let newCL = coverLetterStore.createDuplicate(letter: cL)
                jobAppStore.selectedApp!.selectedCover = newCL  // Assign new instance
                print("new cover letter")
              }
              chatAction(res: jobAppStore.selectedApp?.selectedRes)
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
        .padding()
        .onAppear { print("AI content") }
      }
      .onChange(of: chatProvider.resultsAvailable) { oldValue, newValue in
        if newValue {
          print("New results received!")
          //        processResults()
        }
      }
      .onChange(of: buttons.runRequested) { oldValue, newValue in
        if newValue {
          chatAction(res: jobAppStore.selectedApp?.selectedRes)
        }
      }
    }
  }
  @MainActor
  func processResults(newMessage: String) {
    print("processResults")
    if let cL = jobAppStore.selectedApp?.selectedCover {
      cL.generated = true
      cL.messageHistory.append(.init(content: newMessage, role: .assistant))
      cL.content = newMessage
      print(newMessage)
      isLoading = false
      chatProvider.resultsAvailable = false
    }
  }

  func chatAction(res: Resume?) {
    Task {
      print("chatAction")
      isLoading = true
      defer {
        isLoading = false
        buttons.runRequested = false
      }

      guard let resume = res, let cL = jobAppStore.selectedApp?.selectedCover else {
        print("guard fail")
        return
      }

      switch cL.currentMode {
      case .generate:
          print("generate")
        let prompt = CoverLetterPrompts.generate(
          coverLetter: cL, resume: resume, mode: .generate)
          print("prompt: \(prompt)")
          let myContent: ChatCompletionParameters.Message.ContentType = .text(prompt)
        chatProvider.messageHist = [
          CoverLetterPrompts.systemMessage,
          .init(role: .user, content: myContent),
        ]
        print("message count: \(chatProvider.messageHist.count)")
        cL.messageHistory.append(.init(content: prompt, role: .user))
        let parameters = ChatCompletionParameters(
          messages: chatProvider.messageHist,
          model: .gpt4o20240806,
          responseFormat: .text
        )
        try await chatProvider.startChat(
          parameters: parameters,
          onComplete: { @MainActor newMessage in
            processResults(newMessage: newMessage)
          })

      default:
        // Handle other cases as needed
        break
      }
    }
  }
}
