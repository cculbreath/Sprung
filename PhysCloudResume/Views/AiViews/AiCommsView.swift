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
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    init(service: OpenAIService, query: ResumeApiQuery, res: Binding<Resume?>) {
        _chatProvider = State(initialValue: ResumeChatProvider(service: service))
        _q = State(initialValue: query)
        _myRes = res
    }

    var body: some View {
        execQuery
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
            .alert("API Request Error", isPresented: $showError) {
                Button("OK") {
                    // Reset state when error is acknowledged
                    aiResub = false
                    sheetOn = false
                    isLoading = false
                }
            } message: {
                Text(errorMessage)
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
                        actionRequested: .unevaluated,
                        reviewerComments: "",
                        isTitleNode: currentRevNode!.isTitleNode
                    )
                }
                aiResub = false
                fbnodes = []
            }
            .onChange(of: aiResub) { _, newValue in
                if newValue {
                    chatAction(hasRevisions: true)

                    // Safety timeout to dismiss the review view if AI request takes too long
                    DispatchQueue.main.asyncAfter(deadline: .now() + 180) { // 3 minutes timeout
                        if isLoading && aiResub {
                            print("Request timeout triggered in AiCommsView - dismissing UI")
                            self.showError = true
                            self.errorMessage = "The AI request is taking longer than expected. Please try again later."
                            aiResub = false
                            sheetOn = false
                            isLoading = false
                        }
                    }
                }
            }
    }

    var execQuery: some View {
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
                if let matchedNode = updateNodes.first(where: { $0["id"] as? String == item.id }) {
                    print("\(item.id) found")
                    continue
                } else if let matchedByValue = updateNodes.first(where: { $0["value"] as? String == item.oldValue }), let id = matchedByValue["id"] as? String {
                    // Update revision's ID if matched by value
                    validRevs[index].id = id

                    // Make sure to preserve isTitleNode when matching by value
                    validRevs[index].isTitleNode = matchedByValue["isTitleNode"] as? Bool ?? false

                    print("\(item.id) updated to use ID from matched node. isTitleNode: \(validRevs[index].isTitleNode)")

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
            print("chatAction starting")
            isLoading = true

            do {
                if !hasRevisions {
                    let content: ChatCompletionParameters.Message.ContentType = .text(q.wholeResumeQueryString)

                    chatProvider.messageHist = [
                        q.systemMessage,
                        .init(role: .user, content: content),
                    ]
                } else {
                    chatProvider.messageHist.append(.init(role: .user, content: .text(q.revisionPrompt(fbnodes))))
                }

                let model = OpenAIModelFetcher.getPreferredModel()
                print("Using OpenAI model for resume query: \(model)")
                let parameters = ChatCompletionParameters(
                    messages: chatProvider.messageHist,
                    model: model,
                    responseFormat: .jsonSchema(ResumeApiQuery.revNodeArraySchema)
                )

                // Set up a timeout task that will run if the main task takes too long
                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds - just for checking if progress is made
                    if isLoading && !Task.isCancelled {
                        print("AI operation in progress...")
                    }
                }

                // Execute the API call
                try await chatProvider.startChat(parameters: parameters)

                // Cancel the timeout task since we completed successfully
                timeoutTask.cancel()

                // Check for error messages from the chat provider
                if !chatProvider.errorMessage.isEmpty {
                    throw NSError(domain: "OpenAIError",
                                  code: 1001,
                                  userInfo: [NSLocalizedDescriptionKey: chatProvider.errorMessage])
                }
            } catch {
                print("Error in chatAction: \(error.localizedDescription)")

                // Update error state and show alert
                await MainActor.run {
                    errorMessage = "An error occurred: \(error.localizedDescription)\n\nPlease try again or check your API key configuration."
                    showError = true
                    aiResub = false
                }
            }

            // Always clean up loading state
            await MainActor.run {
                isLoading = false
            }
        }
    }
}
