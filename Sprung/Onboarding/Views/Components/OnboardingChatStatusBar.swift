import SwiftUI

/// Status bar shown at the bottom of the chat panel (model info only)
/// Note: Extraction/agent status is now shown in the full-width BackgroundAgentStatusBar
struct OnboardingChatStatusBar: View {
    let modelStatusDescription: String
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(modelStatusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Change in Settings…") {
                onOpenSettings()
            }
            .buttonStyle(.link)
            .font(.caption)
            Spacer()
        }
    }
}
