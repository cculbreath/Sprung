import SwiftUI

struct OnboardingInterviewBottomBar: View {
    let continueTitle: String
    let isContinueDisabled: Bool
    var continueTooltip: String? = nil
    let onShowSettings: () -> Void
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
            Button("Close") {
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
            .help(continueTooltip ?? "")
        }
    }
}
