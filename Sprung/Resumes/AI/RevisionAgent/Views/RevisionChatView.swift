import SwiftUI

/// Chat-like message stream for the revision agent session.
struct RevisionChatView: View {
    let messages: [RevisionMessage]
    let currentProposal: ChangeProposal?
    let currentQuestion: String?
    let isRunning: Bool
    let onProposalResponse: (ProposalResponse) -> Void
    let onQuestionResponse: (String) -> Void

    @State private var questionAnswer: String = ""
    @State private var shouldAutoScroll = true

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
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
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
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
    }

    // MARK: - Message Row

    @ViewBuilder
    private func messageRow(_ message: RevisionMessage) -> some View {
        switch message.role {
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                    .font(.caption)
                    .padding(.top, 2)

                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)

        case .user:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.top, 2)

                Text(message.content)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)

        case .toolActivity(let toolName):
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
                Text(message.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
