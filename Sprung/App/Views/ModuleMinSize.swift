//
//  ModuleMinSize.swift
//  Sprung
//
//  Lets the active module drive the main window's hard minimum size.
//

import SwiftUI

/// The minimum CONTENT size a module needs, excluding the icon bar.
///
/// The active module publishes this up to `UnifiedAppLayout`, which adds the
/// live icon-bar width and applies the total as the window's hard floor (via
/// `.windowResizability(.contentMinSize)` on the scene). Because the value is
/// derived from a module's collapse state — not from a measured width — it can
/// shrink when panes are collapsed, letting the window then be dragged smaller,
/// with no risk of a sizing feedback loop.
///
/// Modules that don't set it inherit `defaultValue`, a sane compact floor for a
/// single-flexible-column layout. During a module switch two values may briefly
/// coexist; `reduce` takes the max so the window is never momentarily undersized.
struct ModuleMinSizeKey: PreferenceKey {
    static let defaultValue = CGSize(width: 480, height: 650)

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(
            width: max(value.width, next.width),
            height: max(value.height, next.height)
        )
    }
}

extension View {
    /// Publish this module's minimum content size (excluding the icon bar) so
    /// the window floor tracks it.
    func moduleMinContentSize(_ size: CGSize) -> some View {
        preference(key: ModuleMinSizeKey.self, value: size)
    }
}
