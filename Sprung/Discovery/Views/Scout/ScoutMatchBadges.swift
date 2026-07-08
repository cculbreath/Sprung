//
//  ScoutMatchBadges.swift
//  Sprung
//
//  Compact badge row for a recommendation's dimensioned match assessment:
//  the overall verdict plus the four rating dimensions (skills, seniority,
//  location, comp). Shared by the scout report/review UIs so the visual
//  language for a match signal is defined once.
//

import SwiftUI

struct ScoutMatchBadges: View {
    let match: JobScoutMatchAssessment

    var body: some View {
        HStack(spacing: 6) {
            badge(text: verdictLabel, color: verdictColor, filled: true)
            dimensionBadge("Skills", match.skills)
            dimensionBadge("Seniority", match.seniority)
            dimensionBadge("Location", match.locationFit)
            dimensionBadge("Comp", match.compensation)
        }
    }

    private var verdictLabel: String {
        switch match.verdict {
        case .strong: return "Strong match"
        case .promising: return "Promising"
        case .marginal: return "Marginal"
        }
    }

    private var verdictColor: Color {
        switch match.verdict {
        case .strong: return .green
        case .promising: return .blue
        case .marginal: return .orange
        }
    }

    private func dimensionBadge(_ label: String, _ rating: JobScoutMatchAssessment.Rating) -> some View {
        badge(text: "\(label): \(ratingLabel(rating))", color: ratingColor(rating), filled: false)
    }

    private func ratingLabel(_ rating: JobScoutMatchAssessment.Rating) -> String {
        switch rating {
        case .strong: return "strong"
        case .moderate: return "moderate"
        case .weak: return "weak"
        case .unknown: return "—"
        }
    }

    private func ratingColor(_ rating: JobScoutMatchAssessment.Rating) -> Color {
        switch rating {
        case .strong: return .green
        case .moderate: return .blue
        case .weak: return .orange
        case .unknown: return .secondary
        }
    }

    private func badge(text: String, color: Color, filled: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(filled ? .semibold : .regular))
            .foregroundStyle(filled ? color : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(filled ? 0.15 : 0.08))
            )
    }
}
