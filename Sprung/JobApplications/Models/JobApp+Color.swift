//
//  JobApp+Color.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/16/25.
//

import SwiftUI

/// SwiftUI‑only helpers related to `JobApp`.
/// Keeping them in an extension prevents the core data model from depending
/// on the UI framework.
extension JobApp {
    /// Maps a status to the colour used in the UI components.
    static func pillColor(_ status: Statuses) -> Color {
        switch status {
        case .closed: return .gray
        case .followUp: return .yellow
        case .interview: return .pink
        case .submitted: return .indigo
        case .unsubmitted: return .cyan
        case .inProgress: return .mint
        case .new: return .green
        case .abandonned: return .secondary
        case .rejected: return .black
        }
    }

    /// Backwards-compatible mapping when only a raw string is available.
    static func pillColor(_ rawStatus: String) -> Color {
        let trimmed = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = Statuses.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return pillColor(match)
        }

        if trimmed.caseInsensitiveCompare("abandoned") == .orderedSame {
            return pillColor(.abandonned)
        }

        return .black
    }
}
