import SwiftUI

/// ViewModifier to conditionally apply intelligence glow effect when processing,
/// or drop shadow when idle
private struct ConditionalIntelligenceGlow<S: InsettableShape>: ViewModifier {
    let isActive: Bool
    let shape: S

    func body(content: Content) -> some View {
        if isActive {
            content.intelligenceOverlay(in: shape)
        } else {
            content.shadow(color: Color.black.opacity(0.18), radius: 20, y: 16)
        }
    }
}

struct OnboardingInterviewChatPanel: View {
    @Bindable var service: OnboardingInterviewService
    @Bindable var coordinator: OnboardingInterviewCoordinator
    @Bindable var state: OnboardingInterviewViewModel
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
                        ForEach(coordinator.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(20)
                }
                .textSelection(.enabled)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .modifier(ConditionalIntelligenceGlow(
                    isActive: service.isProcessing,
                    shape: RoundedRectangle(cornerRadius: 24, style: .continuous)
                ))
                .onChange(of: coordinator.messages.count) { oldValue, newValue in
                    guard state.shouldAutoScroll, newValue > oldValue,
                          let lastId = coordinator.messages.last?.id else { return }
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
                .onChange(of: coordinator.messages.last?.text ?? "") { _, _ in
                    guard state.shouldAutoScroll, let lastId = coordinator.messages.last?.id else { return }
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
                .onAppear {
                    guard state.shouldAutoScroll, let lastId = coordinator.messages.last?.id else { return }
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
        Task { await service.sendMessage(trimmed) }
    }
}
