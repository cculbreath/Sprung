//
//  ModuleHeader.swift
//  Sprung
//
//  Shared header component for module views.
//

import SwiftUI

/// Shared header component for module views (non-Resume Editor)
struct ModuleHeader: View {
    let title: String
    let subtitle: String
    var actions: (() -> AnyView)? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let actions = actions {
                actions()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// Convenience initializer without actions
extension ModuleHeader {
    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
        self.actions = nil
    }

    /// Typed L1 actions slot — callers compose a `Button`, `HStack`, or any
    /// other view directly instead of pre-erasing to `AnyView` themselves.
    /// Module-scoped actions (per the affordance grammar) belong here rather
    /// than in the app-global toolbar.
    init<Actions: View>(title: String, subtitle: String, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = { AnyView(actions()) }
    }
}

/// Slim single-row identity header for workspaces where vertical space is
/// precious (e.g. the Resume Customizer) — module icon + title on one row,
/// no subtitle, with the same typed actions slot as `ModuleHeader`. Not a
/// replacement for `ModuleHeader`; use where the full two-line header would
/// crowd out workspace content.
struct CompactModuleHeader: View {
    let title: String
    var icon: String? = nil
    var tint: Color = .accentColor
    var actions: (() -> AnyView)? = nil

    init(title: String, icon: String? = nil, tint: Color = .accentColor) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.actions = nil
    }

    init<Actions: View>(
        title: String,
        icon: String? = nil,
        tint: Color = .accentColor,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.actions = { AnyView(actions()) }
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer()

            if let actions = actions {
                actions()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
