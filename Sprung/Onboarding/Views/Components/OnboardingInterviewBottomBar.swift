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
            .buttonBorderShape(.capsule)
            .buttonStyle(.glass)

            Spacer()

            if showBack {
                Button("Go Back") {
                    onBack()
                }
                .buttonBorderShape(.capsule)
                .buttonStyle(.glass)


            }

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)


            Button(continueTitle) {
                onContinue()
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .disabled(isContinueDisabled)
        }
        .padding(.horizontal, 24)
    }
}
