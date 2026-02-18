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

/// Maps a `Proficiency` value to its display color.
func artifactProficiencyColor(_ proficiency: Proficiency) -> Color {
    switch proficiency {
    case .expert: return .green
    case .proficient: return .blue
    case .familiar: return .orange
    }
}
