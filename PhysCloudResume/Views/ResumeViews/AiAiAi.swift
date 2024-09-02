//
//  ChatStructuredOutputDemoView.swift
//  SwiftOpenAIExample
//
//  Created by James Rochabrun on 8/10/24.
//

import Foundation
import SwiftOpenAI
import SwiftUI

struct ChatView: View {
    private let service: OpenAIService
    private let query: ResumeApiQuery

    init(key: String, apiQuery: ResumeApiQuery) {
        service = OpenAIServiceFactory.service(apiKey: key, debugEnabled: true)
        query = apiQuery
    }
    var body: some View {
        ChatViewContents(
            service: service,
            query: query,
            p: query.wholeResumeQueryString
        )
    }
}
struct ChatViewContents: View {
    @State private var q: ResumeApiQuery
    @State private var chatProvider: ChatStructuredOutputProvider
    @State private var isLoading = false
    @State private var prompt: String

    init(service: OpenAIService, query: ResumeApiQuery, p: String) {
        _chatProvider = State(initialValue: ChatStructuredOutputProvider(service: service))
        _q = State(initialValue: query)
        _prompt = State(initialValue: p)
    }

    var body: some View {
        ScrollView {
            VStack {
                textArea
                Text(chatProvider.errorMessage)
                    .foregroundColor(.red)
                chatCompletionResultView
            }
        }
        .overlay(
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    EmptyView()
                }
            }
        )
    }

    var textArea: some View {
        HStack(spacing: 4) {
//            TextField("Enter prompt", text: $prompt, axis: .vertical).lineLimit(5...10)
////                .textFieldStyle(.roundedBorder)
//                .padding()
            Button {
                Task {
                    isLoading = true
                    defer { isLoading = false }  // ensure isLoading is set to false when the

                    let content: ChatCompletionParameters.Message.ContentType = .text(
                        q.wholeResumeQueryString
                    )
                    prompt = ""
                    let parameters = ChatCompletionParameters(
                        messages: [
                            q.systemMessage,
                            .init(
                                role: .user,
                                content: content)],
                        model: .gpt4o20240806,
                        responseFormat:
                                .jsonSchema(
                                    ResumeApiQuery.revNodeArraySchema
                                )
                    )
                    try await chatProvider.startChat(parameters: parameters)
                }
            } label: {
                Image(systemName: "paperplane")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    /// stream = `false`
    var chatCompletionResultView: some View {
        ForEach(Array(chatProvider.messages.enumerated()), id: \.offset) { idx, val in
            VStack(spacing: 0) {
                Text("\(val)")
            }
        }
    }
}
