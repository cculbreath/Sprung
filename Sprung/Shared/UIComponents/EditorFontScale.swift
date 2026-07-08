//
//  EditorFontScale.swift
//  Sprung
//
//  User-adjustable UI font scaling for the resume-editor panes.
//
//  Two independent scales — the job-application list sidebar and the resume
//  tree editor — each driven by View-menu commands and persisted in
//  UserDefaults. `\.fontScale` propagates a multiplier down a pane's view
//  tree; `.scaledFont` reads it so explicitly-sized text grows and shrinks
//  with the command. This is the *editor chrome* font, distinct from the
//  rendered resume's template font sizes (see FontSizePanelView), which it
//  does not touch.
//

import SwiftUI

// MARK: - Environment

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    /// Multiplier applied to text via `.scaledFont`. 1.0 (the default
    /// everywhere the environment isn't set) means no change.
    var fontScale: CGFloat {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

// MARK: - Scaled Font Modifier

private struct ScaledFontModifier: ViewModifier {
    @Environment(\.fontScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// Like `.font(.system(size:weight:design:))` but multiplied by the
    /// enclosing pane's `\.fontScale`. Renders identically to the plain system
    /// font when the scale is 1.0, so it is a drop-in replacement for
    /// `.font(.system(size:...))`.
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design))
    }
}

// MARK: - Persistence + Menu Commands

/// The two independently-adjustable editor font scales, their UserDefaults
/// keys, and the clamp/step logic shared by the View-menu commands. Writing
/// through `UserDefaults.standard` updates the `@AppStorage` readers in the
/// panes, which re-inject `\.fontScale`.
enum EditorFontScale {
    /// Job-application list sidebar (`SidebarView`).
    static let jobListKey = "jobListFontScale"
    /// Resume tree editor content (`ResumeDetailView`).
    static let resumeEditorKey = "resumeEditorFontScale"

    static let defaultScale: Double = 1.0
    static let minScale: Double = 0.7
    static let maxScale: Double = 2.0
    static let step: Double = 0.1

    // MARK: Pure helpers (dependency-free; unit-tested)

    /// Interprets a raw stored value: "absent" (nil) and 0 both mean "never
    /// set", which resolves to the default scale.
    static func normalized(_ stored: Double?) -> Double {
        guard let stored, stored != 0 else { return defaultScale }
        return stored
    }

    /// Clamps a scale to the supported range.
    static func clamped(_ value: Double) -> Double {
        Swift.min(maxScale, Swift.max(minScale, value))
    }

    // MARK: UserDefaults-backed commands

    /// Current stored scale for a key, treating "absent" and 0 as the default.
    static func current(_ key: String) -> Double {
        normalized(UserDefaults.standard.object(forKey: key) as? Double)
    }

    /// Nudge a scale by `delta`, clamped to [minScale, maxScale].
    static func adjust(_ key: String, by delta: Double) {
        UserDefaults.standard.set(clamped(current(key) + delta), forKey: key)
    }

    /// Restore a scale to 100%.
    static func reset(_ key: String) {
        UserDefaults.standard.set(defaultScale, forKey: key)
    }
}
