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
                    .font(.caption)
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
}
