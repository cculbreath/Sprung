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
    /// Maps a `Status` string (case‑insensitive) to a colour used in the UI.
    ///
    /// Usage: `backgroundColor: JobApp.pillColor(status.rawValue)`
    static func pillColor(_ myCase: String) -> Color {
        switch myCase.lowercased() {
        case "closed": return .gray
        case "follow up": return .yellow
        case "interview": return .pink
        case "submitted": return .indigo
        case "unsubmitted": return .cyan
        case "in progress": return .mint
        case "new": return .green
        case "abandoned": return .secondary
        case "abandonned": return .secondary
        case "rejected": return .black
        default: return .black
        }
    }
}
