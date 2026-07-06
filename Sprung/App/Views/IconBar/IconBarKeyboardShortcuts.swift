//
//  IconBarKeyboardShortcuts.swift
//  Sprung
//
//  Keyboard shortcuts for module navigation.
//

import SwiftUI

/// View modifier that adds keyboard shortcuts for module navigation
struct IconBarKeyboardShortcuts: ViewModifier {
    @Environment(ModuleNavigationService.self) private var navigation

    func body(content: Content) -> some View {
        content
            // Module shortcuts 1-9 — must match AppModule.shortcutNumber
            .keyboardShortcut("1", modifiers: .command) { navigation.selectModule(.pipeline) }
            .keyboardShortcut("2", modifiers: .command) { navigation.selectModule(.resumeEditor) }
            .keyboardShortcut("3", modifiers: .command) { navigation.selectModule(.dailyTasks) }
            .keyboardShortcut("4", modifiers: .command) { navigation.selectModule(.events) }
            .keyboardShortcut("5", modifiers: .command) { navigation.selectModule(.contacts) }
            .keyboardShortcut("6", modifiers: .command) { navigation.selectModule(.weeklyReview) }
            .keyboardShortcut("7", modifiers: .command) { navigation.selectModule(.references) }
            .keyboardShortcut("8", modifiers: .command) { navigation.selectModule(.experience) }
            .keyboardShortcut("9", modifiers: .command) { navigation.selectModule(.profile) }

            // Navigation shortcuts
            .keyboardShortcut("[", modifiers: .command) { navigation.selectPreviousModule() }
            .keyboardShortcut("]", modifiers: .command) { navigation.selectNextModule() }
            .keyboardShortcut("\\", modifiers: .command) { navigation.toggleIconBarExpansion() }
    }
}

extension View {
    /// Adds keyboard shortcuts for module navigation
    func moduleNavigationShortcuts() -> some View {
        modifier(IconBarKeyboardShortcuts())
    }
}

// Helper extension to make keyboard shortcut syntax cleaner
private extension View {
    func keyboardShortcut(_ key: Character, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        self.background(
            Button("", action: action)
                .keyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
                .hidden()
        )
    }
}
