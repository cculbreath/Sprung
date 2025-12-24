import SwiftUI

/// Status bar shown at the bottom of the chat panel
struct OnboardingChatStatusBar: View {
    let modelStatusDescription: String
    let isExtractionInProgress: Bool
    let extractionStatusMessage: String?
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
            // Extraction indicator (non-blocking - chat remains enabled)
            if isExtractionInProgress {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(extractionStatusMessage ?? "Extracting...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExtractionInProgress)
    }
}
