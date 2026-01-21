//
//  GlobalKeyboardHandler.swift
//  Sprung
//
//  Handles global keyboard shortcuts for job focus navigation.
//  Uses injected WindowCoordinator for type-safe window coordination.
//

import AppKit
import SwiftUI

/// Handles global keyboard shortcuts for job focus navigation.
/// Created with a WindowCoordinator dependency - NOT a singleton.
@MainActor
final class GlobalKeyboardHandler {
    private let windowCoordinator: WindowCoordinator
    private var eventMonitor: Any?

    init(windowCoordinator: WindowCoordinator) {
        self.windowCoordinator = windowCoordinator
        setupEventMonitor()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Setup

    private func setupEventMonitor() {
        // Add local event monitor (works when app is active)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            // Return nil to consume the event, or return the event to pass it through
            return self.handleKeyboardShortcut(event) ? nil : event
        }
    }

    // MARK: - Event Handling

    /// Returns true if the event was handled and should be consumed
    private func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return false
        }

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Check for Shift modifier shortcuts
        if event.modifierFlags.contains(.shift) {
            switch key {
            case "m":
                // Shift+M - Open Main window with focused job
                windowCoordinator.activateMainWindow()
                return true
            default:
                return false
            }
        }

        // Tab shortcuts (1, 2, 3, 4) - only when job is focused
        guard windowCoordinator.focusState.hasFocusedJob else {
            return false
        }

        switch key {
        case "1":
            windowCoordinator.switchToTab(.listing)
            return true
        case "2":
            windowCoordinator.switchToTab(.resume)
            return true
        case "3":
            windowCoordinator.switchToTab(.coverLetter)
            return true
        case "4":
            windowCoordinator.switchToTab(.submitApp)
            return true
        default:
            return false
        }
    }
}
