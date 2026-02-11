import SwiftUI

/// Chat-like message stream for the revision agent session.
struct RevisionChatView: View {
    let messages: [RevisionMessage]
    let currentProposal: ChangeProposal?
    let currentQuestion: String?
    let isRunning: Bool
    let onProposalResponse: (ProposalResponse) -> Void
    let onQuestionResponse: (String) -> Void
    let onUserMessage: (String) -> Void
    let onAcceptCurrentState: () -> Void

    @State private var questionAnswer: String = ""
    @State private var chatInput: String = ""
    @State private var shouldAutoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }

                        // Active proposal card
                        if let proposal = currentProposal {
                            RevisionProposalView(
                                proposal: proposal,
                                onAccept: { onProposalResponse(.accepted) },
                                onReject: { onProposalResponse(.rejected) },
                                onModify: { feedback in onProposalResponse(.modified(feedback: feedback)) }
                            )
                            .id("proposal")
                        }

                        // Active question
                        if let question = currentQuestion {
                            questionCard(question)
                                .id("question")
                        }

                        // Streaming indicator
                        if isRunning && currentProposal == nil && currentQuestion == nil {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .id("streaming")
                        }

                        // Bottom anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) {
                    if shouldAutoScroll {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: currentProposal != nil) {
                    if shouldAutoScroll {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("proposal", anchor: .top)
                        }
                    }
                }
                .onChange(of: currentQuestion) {
                    if shouldAutoScroll {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("question", anchor: .top)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            chatInputBar
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Chat Input Bar

    @ViewBuilder
    private var chatInputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Send a message...", text: $chatInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                )
                .onSubmit { submitMessage() }

            Button {
                submitMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
            .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if isRunning {
                Button("Accept") {
                    onAcceptCurrentState()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func submitMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatInput = ""
        onUserMessage(text)
    }

    // MARK: - Message Row

    @ViewBuilder
    private func messageRow(_ message: RevisionMessage) -> some View {
        switch message.role {
        case .assistant:
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                    .font(.system(size: 14))
                    .frame(width: 20, alignment: .center)
                    .padding(.top, 4)

                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }

        case .user:
            HStack(alignment: .top, spacing: 10) {
                Spacer(minLength: 60)

                Text(message.content)
                    .font(.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }

        case .toolActivity:
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
                Text(message.content)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 30)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Question Card

    @ViewBuilder
    private func questionCard(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                Text(question)
                    .font(.body)
            }

            TextEditor(text: $questionAnswer)
                .font(.body)
                .frame(minHeight: 40, maxHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.quaternary)
                        )
                )

            HStack {
                Spacer()
                Button("Submit") {
                    let answer = questionAnswer
                    questionAnswer = ""
                    onQuestionResponse(answer)
                }
                .buttonStyle(.borderedProminent)
                .disabled(questionAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }
}
