//
//  WindowCoordinator.swift
//  Sprung
//
//  Coordinates window management and module navigation.
//  Injected via @Environment - NOT a singleton.
//

import AppKit
import SwiftUI

/// Coordinates window management and module navigation.
/// Injected via @Environment - provides type-safe, compile-checked window coordination.
@Observable
@MainActor
final class WindowCoordinator {

    // MARK: - Window References

    /// Weak reference to main window (set by SprungApp on window creation)
    weak var mainWindow: NSWindow?

    // MARK: - State

    /// The shared job focus state
    let focusState: UnifiedJobFocusState

    /// Module navigation service (for cross-component navigation commands)
    var moduleNavigation: ModuleNavigationService?

    init(focusState: UnifiedJobFocusState) {
        self.focusState = focusState
    }

    // MARK: - Window Activation

    /// Activate the main window, optionally focusing a specific job and tab
    func activateMainWindow(job: JobApp? = nil, tab: TabList? = nil) {
        // Update focus state if job provided
        if let job = job {
            focusState.focusedJob = job
        }
        if let tab = tab {
            focusState.focusedTab = tab
        }

        // Find or activate main window
        if let window = mainWindow ?? findMainWindow() {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            Logger.info("Activated main window", category: .ui)
        } else {
            // Main window is managed by SwiftUI's WindowGroup - just activate the app
            NSApp.activate(ignoringOtherApps: true)
            Logger.info("Requested main window activation", category: .ui)
        }
    }

    // MARK: - Tab Navigation

    /// Switch to a specific tab (works from any context)
    func switchToTab(_ tab: TabList) {
        focusState.focusedTab = tab

        // Ensure we're in Resume Editor module
        moduleNavigation?.selectModule(.resumeEditor)

        activateMainWindow()
    }

    // MARK: - Private Helpers

    private func findMainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.identifier?.rawValue == "myApp" || window.title.isEmpty
        }
    }
}
