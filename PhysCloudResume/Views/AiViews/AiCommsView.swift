//
//  AiCommsView.swift
//  SwiftOpenAIExample
//
//  Created by James Rochabrun on 8/10/24.
//

import Foundation
import SwiftOpenAI
import SwiftUI

struct AiCommsView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @State private var q: ResumeApiQuery
    @State private var chatProvider: ResumeChatProvider
    @State private var revisions: [ProposedRevisionNode] = []
    @State private var currentRevNode: ProposedRevisionNode? = nil
    @State var currentFeedbackNode: FeedbackNode? = nil
    @State private var isLoading = false
    @State private var sheetOn: Bool = false
    @State private var aiResub: Bool = false
    @Binding var myRes: Resume?
    @State private var fbnodes: [FeedbackNode] = []
    init(service: OpenAIService, query: ResumeApiQuery, res: Binding<Resume?>) {
        _chatProvider = State(initialValue: ResumeChatProvider(service: service))
        _q = State(initialValue: query)
        _myRes = res
    }

    var body: some View {
        exec_query
            .sheet(isPresented: $sheetOn) {
                print("sheet dismissed")
            } content: {
                if sheetOn {
                    ReviewView(
                        revisionArray: $revisions,
                        feedbackArray: $fbnodes,
                        currentFeedbackNode: $currentFeedbackNode,
                        currentRevNode: $currentRevNode,
                        sheetOn: $sheetOn,
                        selRes: $myRes,
                        aiResub: $aiResub
                    )
                    .frame(minWidth: 650)
                }
            }
            .onChange(of: chatProvider.lastRevNodeArray) { _, newValue in
                sheetOn = true
                revisions = validateRevs(res: myRes, revs: newValue) ?? [] // Updated this call
                currentRevNode = revisions[0]
                if currentRevNode != nil {
                    currentFeedbackNode = FeedbackNode(
                        id: currentRevNode!.id,
                        originalValue: currentRevNode!.oldValue,
                        proposedRevision: currentRevNode!.newValue,
                        actionRequested: .unevaluated
                    )
                }
                aiResub = false
                fbnodes = []
            }
            .onChange(of: aiResub) { _, newValue in
                if newValue {
                    chatAction(hasRevisions: true)
                }
            }
    }

    var exec_query: some View {
        HStack(spacing: 4) {
            VStack {
                if !isLoading {
                    if
                        (myRes?.rootNode?.aiStatusChildren ?? 0)
                        > 0
                    {
                        Button(action: {
                            print("Notloading")
                            chatAction()
                        }) {
                            Image("ai-squiggle")
                                .font(.system(size: 20, weight: .regular))
                        }
                        .help("Create new Résumé")
                    } else {
                        Image("ai-squiggle.slash").font(.system(size: 20, weight: .regular)).help("Select fields for ai update")
                    }
                } else {
                    ProgressView().scaleEffect(0.75, anchor: .center) // Show a loading indicator when isLoading is true
                }
            }
            .padding()
        }
    }

    // Validation function for revisions
    func validateRevs(res: Resume?, revs: [ProposedRevisionNode]) -> [ProposedRevisionNode]? {
        print("Validating revisions...")
        var validRevs = revs
        if let myRes = res {
            let updateNodes = myRes.getUpdatableNodes()

            for (index, item) in validRevs.enumerated() {
                // Check by ID first
                if let matchedNode = updateNodes.first(where: { $0["id"] == item.id }) {
                    print("\(item.id) found")
                    continue
                } else if let matchedByValue = updateNodes.first(where: { $0["oldValue"] == item.oldValue }), let id = matchedByValue["id"] {
                    // Update revision's ID if matched by value
                    validRevs[index].id = id
                    print("\(item.id) updated")

                } else {
                    print("No match found for revision: \(item.id) - \(item.oldValue)")
                }
            }
            return validRevs
        }
        return nil
    }

    func chatAction(hasRevisions: Bool = false) {
        if let jobApp = jobAppStore.selectedApp {
            jobApp.status = .inProgress
        }
        Task {
            print("chatAction")
            isLoading = true
            defer { isLoading = false } // ensure isLoading is set to false when the task completes

            if !hasRevisions {
                let content: ChatCompletionParameters.Message.ContentType = .text(q.wholeResumeQueryString)

                chatProvider.messageHist = [
                    q.systemMessage,
                    .init(role: .user, content: content),
                ]
            } else {
                chatProvider.messageHist.append(.init(role: .user, content: .text(q.revisionPrompt(fbnodes))))
            }

            let parameters = ChatCompletionParameters(
                messages: chatProvider.messageHist,
                model: .gpt4o20240806,
                responseFormat: .jsonSchema(ResumeApiQuery.revNodeArraySchema)
            )
            try await chatProvider.startChat(parameters: parameters)
        }
    }
}
