import SwiftUI

/// Chat input composer with send/queue/interrupt buttons
struct OnboardingChatComposerView: View {
    @Binding var text: String
    let isEditable: Bool
    let isProcessing: Bool
    let isWaitingForValidation: Bool
    let queuedMessageCount: Int
    let onSend: (String) -> Void
    let onInterrupt: (String) -> Void

    @State private var composerHeight: CGFloat = ChatComposerTextView.minimumHeight

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSendDisabled: Bool {
        !hasText || !isEditable || isWaitingForValidation
    }

    private var queueButtonTitle: String {
        if queuedMessageCount > 0 {
            return "Queue (\(queuedMessageCount + 1))"
        }
        return "Queue"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ChatComposerTextView(
                text: $text,
                isEditable: isEditable,
                onSubmit: { text in
                    onSend(text)
                },
                measuredHeight: $composerHeight
            )
            .frame(height: min(max(composerHeight, 44), 140))
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
            )

            if isProcessing {
                // When busy: Queue button + Interrupt button (stacked vertically)
                VStack(spacing: 4) {
                    Button(action: {
                        onSend(text)
                    }, label: {
                        Label(queueButtonTitle, systemImage: "clock")
                            .frame(maxWidth: .infinity)
                    })
                    .buttonStyle(.bordered)
                    .disabled(isSendDisabled)
                    .help("Add message to queue - will be sent when current operation completes")

                    Button(action: {
                        onInterrupt(text)
                    }, label: {
                        Label("Interrupt", systemImage: "exclamationmark.bubble.fill")
                            .frame(maxWidth: .infinity)
                    })
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isSendDisabled)
                    .help("Stop current operation and send this message immediately")
                }
                .frame(width: 100)
            } else {
                // When idle: Send button
                Button(action: {
                    onSend(text)
                }, label: {
                    Label("Send", systemImage: "paperplane.fill")
                })
                .buttonStyle(.borderedProminent)
                .disabled(isSendDisabled)
                .help(isWaitingForValidation ? "Submit or cancel the validation dialog to continue" : "")
            }
        }
    }
}
