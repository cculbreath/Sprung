//
//  BorderlessOverlayWindow.swift
//  Sprung
//
//
import Cocoa

/// Custom overlay window for the onboarding interview.
/// - Movable by dragging the window background (respects interactive controls)
/// - Uses system shadow for proper hit testing
/// - Not always-on-top (normal window level)
final class BorderlessOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // Use system shadow - properly respects hit testing
        hasShadow = true
        // Normal level - not always on top
        level = .normal
        // Allow window to be moved by dragging its background
        // This respects the responder chain - interactive controls (lists, scroll views,
        // drag handles) receive their events first, only unhandled drags move the window
        isMovableByWindowBackground = true
        collectionBehavior = [.transient, .moveToActiveSpace]
        contentView?.wantsLayer = true
        contentView?.layer?.masksToBounds = false
    }
}
