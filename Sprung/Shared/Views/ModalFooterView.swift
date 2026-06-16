//
//  ModalFooterView.swift
//  Sprung
//
//  Shared Cancel + primary-action footer for modal sheets. Unifies the chrome
//  that had drifted across sheets (inconsistent keyboard shortcuts, divergent
//  error placement). Standardizes on .cancelAction / .defaultAction and a single
//  error location (above the button row).
//

import SwiftUI

struct ModalFooterView: View {
    var cancelLabel: String = "Cancel"
    let primaryLabel: String
    /// Optional SF Symbol shown alongside the primary label (nil = text-only).
    var primaryIcon: String? = nil
    var isDisabled: Bool = false
    /// When true, the primary button shows a spinner and is disabled.
    var isProcessing: Bool = false
    /// Inline error surfaced above the buttons (nil/empty = hidden).
    var error: String? = nil
    /// Optional middle button (e.g. "Manual Entry").
    var secondaryLabel: String? = nil
    var onSecondary: (() -> Void)? = nil
    let onCancel: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(cancelLabel, action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if let secondaryLabel, let onSecondary {
                    Button(secondaryLabel, action: onSecondary)
                }

                Button(action: onPrimary) {
                    if isProcessing {
                        ProgressView().controlSize(.small)
                    } else if let primaryIcon {
                        Label(primaryLabel, systemImage: primaryIcon)
                    } else {
                        Text(primaryLabel)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled || isProcessing)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}
