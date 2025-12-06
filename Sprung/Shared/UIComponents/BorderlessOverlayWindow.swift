//
//  BorderlessOverlayWindow.swift
//  Sprung
//
//
import Cocoa

/// Custom overlay window for the onboarding interview.
/// - Movable by dragging anywhere on the window
/// - Uses system shadow for proper hit testing
/// - Not always-on-top (normal window level)
final class BorderlessOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Track if we're currently dragging the window
    private var isDragging = false
    private var initialMouseLocation: NSPoint = .zero

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
        isMovableByWindowBackground = true
        collectionBehavior = [.transient, .moveToActiveSpace]
        // Allow window to be moved by dragging its background
        contentView?.wantsLayer = true
        contentView?.layer?.masksToBounds = false
    }

    // Enable window dragging from anywhere
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        initialMouseLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let currentLocation = event.locationInWindow
        var newOrigin = frame.origin
        newOrigin.x += currentLocation.x - initialMouseLocation.x
        newOrigin.y += currentLocation.y - initialMouseLocation.y
        setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }
}
