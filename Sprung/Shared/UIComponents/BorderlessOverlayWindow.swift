//
//  BorderlessOverlayWindow.swift
//  Sprung
//
//
import Cocoa
import SwiftUI

/// Custom overlay window for the onboarding interview.
/// - Movable via dedicated drag handle (not background - conflicts with SwiftUI drag gestures)
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
        // IMPORTANT: Do NOT use isMovableByWindowBackground - it conflicts with SwiftUI's
        // onDrag/onDrop gestures for list reordering. Window movement is handled via a
        // dedicated drag handle using performDrag(with:) instead.
        isMovableByWindowBackground = false
        collectionBehavior = [.transient, .moveToActiveSpace]
        contentView?.wantsLayer = true
        contentView?.layer?.masksToBounds = false
    }
}

/// A SwiftUI view that acts as a window drag handle for BorderlessOverlayWindow.
/// Place this at the top of your window content to allow users to drag the window.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragHandleView {
        WindowDragHandleView()
    }

    func updateNSView(_ nsView: WindowDragHandleView, context: Context) {}
}

/// Custom NSView that initiates window dragging on mouse down.
final class WindowDragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
