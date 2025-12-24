import SwiftUI

/// Chat input composer with send/stop button
struct OnboardingChatComposerView: View {
    @Binding var text: String
    let isEditable: Bool
    let isProcessing: Bool
    let isWaitingForValidation: Bool
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var composerHeight: CGFloat = ChatComposerTextView.minimumHeight

    private var isSendDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !isEditable ||
            isWaitingForValidation
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
                Button(action: {
                    onCancel()
                }, label: {
                    Label("Stop", systemImage: "stop.fill")
                })
                .buttonStyle(.bordered)
            } else {
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
