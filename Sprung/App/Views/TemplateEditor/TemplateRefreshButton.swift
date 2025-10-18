//
//  TemplateRefreshButton.swift
//  Sprung
//
//  Provides a shared refresh/save button that animates using SF Symbol effects.
//

import SwiftUI

struct TemplateRefreshButton: View {
    var hasUnsavedChanges: Bool
    var isAnimating: Bool
    var isEnabled: Bool = true
    var help: String?
    var action: () -> Void

    enum State {
        case dirty
        case saving
        case clean

        init(hasUnsavedChanges: Bool, isAnimating: Bool) {
            if isAnimating {
                self = .saving
            } else if hasUnsavedChanges {
                self = .dirty
            } else {
                self = .clean
            }
        }

        var symbolName: String {
            switch self {
            case .dirty:
                return "custom.arrow.trianglehead.counterclockwise.badge.ellipsis"
            case .saving:
                return "arrow.trianglehead.2.counterclockwise"
            case .clean:
                return "checkmark.arrow.trianglehead.counterclockwise"
            }
        }

        func helpText(custom: String?) -> String {
            if let custom { return custom }
            switch self {
            case .dirty:
                return "Save changes and refresh"
            case .saving:
                return "Generating preview…"
            case .clean:
                return "Refresh preview"
            }
        }
    }

    var body: some View {
        let state = State(hasUnsavedChanges: hasUnsavedChanges, isAnimating: isAnimating)
        Button(action: action) {
            refreshImage(for: state.symbolName)
                .symbolEffect(
                    .rotate,
                    options: isAnimating ? .repeat(.continuous) : .default,
                    isActive: isAnimating
                )
        }
        .buttonStyle(.borderless)
        .help(state.helpText(custom: help))
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private func refreshImage(for symbolName: String) -> some View {
        if symbolName.hasPrefix("custom.") {
            Image(symbolName)
        } else {
            Image(systemName: symbolName)
        }
    }
}
