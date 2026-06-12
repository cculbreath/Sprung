import SwiftUI

/// Chat input composer: Send always queues (delivered at the next safe
/// boundary while the assistant is working); Stop is the explicit interrupt.
struct OnboardingChatComposerView: View {
    @Binding var text: String
    let isEditable: Bool
    let isProcessing: Bool     // True when any processing is happening
    let isWaitingForValidation: Bool
    let onSend: (String) -> Void
    let onStop: () -> Void

    @State private var composerHeight: CGFloat = ChatComposerTextView.minimumHeight

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSendDisabled: Bool {
        !hasText || !isEditable || isWaitingForValidation
    }


    var body: some View {
        // Single row layout - no vertical stacking that causes layout shifts
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

            // Button stack - fixed layout, visibility changes via opacity
            VStack(alignment: .trailing, spacing: 4) {
                // Primary button - Send or Queue (fixed width to prevent layout shift)
                // While the assistant is working, sending queues the message for
                // delivery at the next safe boundary (label communicates this)
                Button(action: {
                    onSend(text)
                }, label: {
                    Label(isProcessing ? "Queue" : "Send",
                          systemImage: isProcessing ? "clock" : "paperplane.fill")
                        .frame(minWidth: 60)
                })
                .buttonStyle(.borderedProminent)
                .tint(isProcessing ? .gray : .accentColor)
                .disabled(isSendDisabled)
                .help(isProcessing
                      ? "Add message to queue - delivered when the assistant reaches a safe boundary"
                      : (isWaitingForValidation ? "Submit or cancel the validation dialog to continue" : ""))

                // Stop button - the explicit interrupt; always in layout,
                // opacity controls visibility
                Button(action: {
                    onStop()
                }, label: {
                    Label("Stop", systemImage: "stop.fill")
                })
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .help("Stop all processing, clear queued messages, and silence incoming tool calls")
                .opacity(isProcessing ? 1 : 0)
                .allowsHitTesting(isProcessing)
            }
        }
    }
}
