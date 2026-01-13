import SwiftUI

/// Chat input composer with send/queue and context-aware stop/interrupt button
struct OnboardingChatComposerView: View {
    @Binding var text: String
    let isEditable: Bool
    let isStreaming: Bool      // True when LLM is actively streaming (glow on)
    let isProcessing: Bool     // True when any processing is happening
    let isWaitingForValidation: Bool
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
                // Show Queue only when LLM is actively streaming to avoid interrupting
                Button(action: {
                    onSend(text)
                }, label: {
                    Label(isStreaming ? "Queue" : "Send",
                          systemImage: isStreaming ? "clock" : "paperplane.fill")
                        .frame(minWidth: 60)
                })
                .buttonStyle(.borderedProminent)
                .tint(isStreaming ? .gray : .accentColor)
                .disabled(isSendDisabled)
                .help(isStreaming
                      ? "Add message to queue - will be sent when response completes"
                      : (isWaitingForValidation ? "Submit or cancel the validation dialog to continue" : ""))

                // Stop/Interrupt button - always in layout, opacity controls visibility
                Group {
                    if hasText && isProcessing {
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
                .opacity(isProcessing ? 1 : 0)
                .allowsHitTesting(isProcessing)
            }
        }
    }
}
