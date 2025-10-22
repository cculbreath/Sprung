import SwiftUI

struct OnboardingInterviewBottomBar: View {
    let showBack: Bool
    let continueTitle: String
    let isContinueDisabled: Bool
    let onShowSettings: () -> Void
    let onBack: () -> Void
    let onCancel: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Options…") {
                onShowSettings()
            }
            .buttonStyle(.bordered)

            Spacer()

            if showBack {
                Button("Go Back") {
                    onBack()
                }
            }

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)

            Button(continueTitle) {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isContinueDisabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}
