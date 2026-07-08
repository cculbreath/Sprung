//
//  JobApp+Color.swift
//  Sprung
//
//  STATUS role, JobApp stage palette (see plans/ux-consistency-plan-2026-07-08.md
//  §3/§6a, decision E1(B)): the stage → Color mapping lives in exactly one
//  place — `Statuses.color` (JobApp.swift) — so every surface that shows a
//  stage (Pipeline columns, Customizer sidebar pills, banners, sidebar
//  sections) reads the identical palette. Nothing here re-derives or
//  shadows that mapping; it is only ever looked up.
//
import SwiftUI
/// SwiftUI‑only helpers related to `JobApp`.
/// Keeping them in an extension prevents the core data model from depending
/// on the UI framework.
extension JobApp {
    /// Public accessor for the JobApp stage palette. Delegates to the single
    /// source of truth, `Statuses.color` — do not add a second mapping here
    /// or anywhere else; new call sites should prefer `status.color`
    /// directly, but this stays for existing consumers (e.g.
    /// `JobAppSectionView`).
    static func pillColor(_ status: Statuses) -> Color {
        status.color
    }
}
