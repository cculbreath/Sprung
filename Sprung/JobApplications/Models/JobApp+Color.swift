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
        status.color
    }
}
