import SwiftUI

/// ViewModifier to conditionally apply intelligence glow effect
private struct ConditionalIntelligenceGlow<S: InsettableShape>: ViewModifier {
    let isActive: Bool
    let shape: S

    func body(content: Content) -> some View {
        if isActive {
            content.intelligenceOverlay(in: shape)
        } else {
            content
        }
    }
}

struct OnboardingInterviewChatPanel: View {
    @Bindable var service: OnboardingInterviewService
    @Bindable var state: OnboardingInterviewViewModel
    let actions: OnboardingInterviewActionHandler
    let modelStatusDescription: String
    let onOpenSettings: () -> Void

    var body: some View {
        let horizontalPadding: CGFloat = 32
        let topPadding: CGFloat = 28
        let bottomPadding: CGFloat = 28
        let sectionSpacing: CGFloat = 20

        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(service.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(20)
                }
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .modifier(ConditionalIntelligenceGlow(
                    isActive: service.isProcessing,
                    shape: RoundedRectangle(cornerRadius: 24, style: .continuous)
                ))
                .onChange(of: service.messages.count) { _, _ in
                    guard state.shouldAutoScroll, let lastId = service.messages.last?.id else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
                .onAppear {
                    guard state.shouldAutoScroll, let lastId = service.messages.last?.id else { return }
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
            .padding(.top, topPadding)
            .padding(.horizontal, horizontalPadding)

            if !service.nextQuestions.isEmpty {
                Divider()
                    .padding(.top, sectionSpacing)
                    .padding(.horizontal, horizontalPadding)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(service.nextQuestions) { question in
                            Button(action: { send(question.text) }) {
                                Text(question.text)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                }
                .padding(.horizontal, horizontalPadding)
            }

            Divider()
                .padding(.top, sectionSpacing)
                .padding(.horizontal, horizontalPadding)

            HStack(alignment: .center, spacing: 12) {
                TextField(
                    "Type your response…",
                    text: Binding(
                        get: { state.userInput },
                        set: { state.userInput = $0 }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(!service.isActive || service.isProcessing)
                .onSubmit { send(state.userInput) }

                Button {
                    send(state.userInput)
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    state.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        !service.isActive ||
                        service.isProcessing
                )
            }
            .padding(.top, sectionSpacing)
            .padding(.horizontal, horizontalPadding)

            HStack(spacing: 6) {
                Text(modelStatusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Change in Settings…") {
                    onOpenSettings()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .padding(.top, 8)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
        }
        .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.userInput = ""
        Task { await actions.sendMessage(trimmed) }
    }
}
