import SwiftUI

/// Shared badge pill used across artifact sub-views for displaying tags, skills, and labels.
func artifactBadgePill(_ text: String, color: Color) -> some View {
    Text(text)
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .cornerRadius(4)
}
