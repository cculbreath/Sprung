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
  @Binding var selRes: Resume?
  @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
  @Binding var buttons: CoverLetterButtons
  @State var aiMode: CoverAiMode = .none

  var body: some View {
    if selRes != nil {
      CoverLetterAiContentView(
        service: OpenAIServiceFactory.service(
          apiKey: openAiApiKey, debugEnabled: false),
        aiMode: aiMode,
        myRes: $selRes,
        buttons: $buttons)
      .onAppear { print("Ai Cover Letter") }
    } else {
      EmptyView()      .onAppear { print("Womp") }

    }
  }
}

struct CoverLetterAiContentView: View {
  @Environment(CoverLetterStore.self) private var coverLetterStore

  @State var aiMode: CoverAiMode
  @State var isLoading = false
  @Binding var myRes: Resume?
  @Binding var buttons: CoverLetterButtons
  let service: OpenAIService

  // Use @Bindable for chatProvider
  @Bindable var chatProvider: CoverChatProvider

  init(
    service: OpenAIService,
    aiMode: CoverAiMode,
    myRes: Binding<Resume?>,
    buttons: Binding<CoverLetterButtons>
  ) {
    self.service = service
    self._aiMode = State(initialValue: aiMode)
    self._myRes = myRes
    self._buttons = buttons
    self.chatProvider = CoverChatProvider(service: service)
  }

  var body: some View {
    if let cL = coverLetterStore.cL {
      HStack(spacing: 4) {
        VStack {
          if !isLoading {
            Button(action: {
              print("Not loading")
              if !cL.generated {
                cL.currentMode = .generate
              } else {
                let newCL = coverLetterStore.createDuplicate(letter: cL)
                coverLetterStore.cL = newCL  // Assign new instance
                print("new cover letter")
              }
              chatAction()
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
          chatAction()
        }
      }
    }}
  @MainActor
  func processResults(newMessage: String) {
    print("processResults")
    if let cL = coverLetterStore.cL {
      cL.generated = true
      cL.messageHistory.append(.init(content: newMessage, role: .assistant))
      cL.content = newMessage
      print(newMessage)
      isLoading = false
      chatProvider.resultsAvailable = false
    }
  }

  func chatAction() {
    Task {
      print("chatAction")
      isLoading = true
      defer {
        isLoading = false
        buttons.runRequested = false
      }

      guard let resume = myRes, let cL = coverLetterStore.cL else {
        print("guard fail")
        return
      }

      switch cL.currentMode {
        case .generate:
          let prompt = CoverLetterPrompts.generate(
            coverLetter: cL, resume: resume, mode: aiMode)
          let myContent = ChatCompletionParameters.Message.ContentType.text(prompt)
          chatProvider.messageHist = [
            CoverLetterPrompts.systemMessage, .init(role: .user, content: myContent)
          ]
          print("message count: \(chatProvider.messageHist.count)")
          cL.messageHistory.append(.init(content: prompt, role: .user))
          let parameters = ChatCompletionParameters(
            messages: chatProvider.messageHist,
            model: .gpt4o20240806,
            responseFormat: .text
          )
          try await chatProvider.startChat(parameters: parameters, onComplete: { @MainActor newMessage in
            processResults(newMessage: newMessage)
          })

        default:
          // Handle other cases as needed
          break
      }
    }
  }
}
