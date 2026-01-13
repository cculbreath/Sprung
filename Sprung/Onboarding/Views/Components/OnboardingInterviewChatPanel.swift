import SwiftUI

struct OnboardingInterviewChatPanel: View {
    let coordinator: OnboardingInterviewCoordinator
    @Bindable var state: OnboardingInterviewViewModel
    let modelStatusDescription: String
    let onOpenSettings: () -> Void

    @State private var exportErrorMessage: String?
    @State private var showMessageFailedAlert = false

    private let horizontalPadding: CGFloat = 20
    private let topPadding: CGFloat = 16
    private let bottomPadding: CGFloat = 16
    private let sectionSpacing: CGFloat = 14

    private var bannerVisible: Bool {
        !(coordinator.ui.modelAvailabilityMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var isWaitingForValidation: Bool {
        coordinator.pendingValidationPrompt?.mode == .validation
    }

    var body: some View {
        VStack(spacing: 0) {
            // Banner
            if bannerVisible, let alert = coordinator.ui.modelAvailabilityMessage {
                OnboardingChatBannerView(
                    text: alert,
                    onOpenSettings: onOpenSettings,
                    onDismiss: {
                        coordinator.clearModelAvailabilityMessage()
                    }
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Message List
            OnboardingChatMessageList(
                coordinator: coordinator,
                shouldAutoScroll: $state.shouldAutoScroll,
                onExportError: { errorMessage in
                    exportErrorMessage = errorMessage
                }
            )
            .padding(.top, bannerVisible ? 8 : topPadding)
            .padding(.horizontal, horizontalPadding)

            Divider()
                .padding(.top, sectionSpacing)
                .padding(.horizontal, horizontalPadding)

            // Composer
            OnboardingChatComposerView(
                text: $state.userInput,
                isEditable: coordinator.ui.isActive,
                isStreaming: coordinator.ui.isStreaming,
                isProcessing: coordinator.ui.isProcessing,
                isWaitingForValidation: isWaitingForValidation,
                onSend: { text in
                    send(text)
                },
                onInterrupt: { text in
                    interrupt(text)
                },
                onStop: {
                    stop()
                }
            )
            .padding(.top, sectionSpacing)
            .padding(.horizontal, horizontalPadding)

            // Status Bar (model info only - extraction status is shown in full-width BackgroundAgentStatusBar)
            OnboardingChatStatusBar(
                modelStatusDescription: modelStatusDescription,
                onOpenSettings: onOpenSettings
            )
            .padding(.top, 8)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
        }
        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: coordinator.ui.modelAvailabilityMessage)
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { _ in exportErrorMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .alert("Message Failed to Send", isPresented: $showMessageFailedAlert) {
            Button("OK", role: .cancel) {
                coordinator.ui.clearFailedMessage()
            }
        } message: {
            Text(coordinator.ui.failedMessageError ?? "The message could not be sent. Please try again.")
        }
        .onChange(of: coordinator.ui.failedMessageText) { _, newValue in
            // When a message fails, restore the text to the input box and show alert
            if let text = newValue {
                state.userInput = text
                showMessageFailedAlert = true
            }
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.shouldAutoScroll = true
        state.userInput = ""
        Task {
            await coordinator.sendChatMessage(trimmed)
        }
    }

    private func interrupt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.shouldAutoScroll = true
        state.userInput = ""
        Task {
            await coordinator.interruptWithMessage(trimmed)
        }
    }

    private func stop() {
        Task {
            await coordinator.stopProcessing()
        }
    }
}
