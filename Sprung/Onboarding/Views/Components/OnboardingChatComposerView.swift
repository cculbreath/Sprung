import SwiftUI

/// Chat input composer with send/queue and context-aware stop/interrupt button
struct OnboardingChatComposerView: View {
    @Binding var text: String
    let isEditable: Bool
    let isProcessing: Bool
    let isWaitingForValidation: Bool
    let queuedMessageCount: Int
    let onSend: (String) -> Void
    let onInterrupt: (String) -> Void
    let onStop: () -> Void

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
        VStack(alignment: .trailing, spacing: 6) {
            // Main input row - text field + primary button (Send or Queue)
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

                // Primary button - consistent size, changes appearance based on state
                Button(action: {
                    onSend(text)
                }, label: {
                    Label(isProcessing ? queueButtonTitle : "Send",
                          systemImage: isProcessing ? "clock" : "paperplane.fill")
                })
                .buttonStyle(.borderedProminent)
                .tint(isProcessing ? .gray : .accentColor)
                .disabled(isSendDisabled)
                .help(isProcessing
                      ? "Add message to queue - will be sent when current operation completes"
                      : (isWaitingForValidation ? "Submit or cancel the validation dialog to continue" : ""))
            }

            // Stop/Interrupt button - appears below when processing
            if isProcessing {
                if hasText {
                    Button(action: {
                        onInterrupt(text)
                    }, label: {
                        Label("Interrupt", systemImage: "exclamationmark.bubble.fill")
                    })
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                    .disabled(!isEditable || isWaitingForValidation)
                    .help("Stop current operation and send this message immediately")
                } else {
                    Button(action: {
                        onStop()
                    }, label: {
                        Label("Stop", systemImage: "stop.fill")
                    })
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    .help("Stop all processing, clear queue, and silence incoming tool calls")
                }
            }
        }
    }
}
