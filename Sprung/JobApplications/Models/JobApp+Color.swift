//
//  JobApp+Color.swift
//  Sprung
//
//
import SwiftUI
/// SwiftUI‑only helpers related to `JobApp`.
/// Keeping them in an extension prevents the core data model from depending
/// on the UI framework.
extension JobApp {
    /// Maps a status to the colour used in the UI components.
    static func pillColor(_ status: Statuses) -> Color {
        switch status {
        case .new: return .blue
        case .researching: return .purple
        case .applying: return .orange
        case .submitted: return .green
        case .interview: return .teal
        case .offer: return .yellow
        case .accepted: return .mint
        case .rejected: return .red
        case .withdrawn: return .gray
        // Legacy statuses
        case .inProgress: return .orange
        case .unsubmitted: return .gray
        case .closed: return .secondary
        case .followUp: return .yellow
        case .abandonned: return .gray
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
