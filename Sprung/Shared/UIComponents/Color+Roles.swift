//
//  Color+Roles.swift
//  Sprung
//
//  The STATUS color role (see plans/ux-consistency-plan-2026-07-08.md §3,
//  decision E1(B)): semantic, app-global meaning, expressed as SwiftUI's
//  system semantic colors rather than hand-picked hex values. Native,
//  low-maintenance, and instantly legible regardless of the surface it
//  appears on.
//
//  This is the shared STATUS vocabulary only. IDENTITY tints (module/section
//  color) stay hand-tuned per module and are not defined here.
//

import SwiftUI

extension Color {
    /// STATUS role — something is waiting/not yet acted on.
    static let statusPending = Color.orange

    /// STATUS role — something completed or was sent successfully
    /// (e.g. "submitted").
    static let statusSuccess = Color.green

    /// STATUS role — something failed, or the action is destructive.
    static let statusFailed = Color.red

    /// STATUS role — neutral, informational state (no success/failure
    /// judgment implied).
    static let statusInformational = Color.blue
}

// Bridge the STATUS tokens into the `ShapeStyle` leading-dot position so they
// work directly in `.foregroundStyle(.statusFailed)` / `.fill(.statusSuccess)`
// / `.tint(.statusPending)` — exactly how SwiftUI's own `.red`/`.blue` resolve.
// A plain `Color` static only resolves where the compiler already wants a
// `Color`; this extension covers every `ShapeStyle` context too.
extension ShapeStyle where Self == Color {
    /// STATUS role — waiting/not yet acted on.
    static var statusPending: Color { .statusPending }

    /// STATUS role — completed or sent successfully.
    static var statusSuccess: Color { .statusSuccess }

    /// STATUS role — failed or destructive.
    static var statusFailed: Color { .statusFailed }

    /// STATUS role — neutral, informational.
    static var statusInformational: Color { .statusInformational }
}
