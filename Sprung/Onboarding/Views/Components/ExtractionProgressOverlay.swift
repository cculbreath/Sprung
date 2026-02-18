import SwiftUI

struct ExtractionProgressOverlay: View {
    let items: [ExtractionProgressItem]
    let statusText: String?
    var body: some View {
        VStack(spacing: 28) {
            AnimatedThinkingText(statusMessage: statusText)
            VStack(alignment: .leading, spacing: 18) {
                Text("Processing r\u{00e9}sum\u{00e9}\u{2026}")
                    .font(.headline)
                ExtractionProgressChecklistView(items: items)
            }
            .padding(.vertical, 26)
            .padding(.horizontal, 26)
            .frame(maxWidth: 420, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                    .blendMode(.plusLighter)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 28, y: 22)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
