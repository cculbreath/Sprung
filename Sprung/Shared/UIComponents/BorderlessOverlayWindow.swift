//
//  BorderlessOverlayWindow.swift
//  Sprung
//
//  Created by Christopher Culbreath on 10/22/25.
//


import Cocoa

final class BorderlessOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .normal
        collectionBehavior = [.moveToActiveSpace]
        ignoresMouseEvents = false
        collectionBehavior = [.transient, .moveToActiveSpace]

        // Allow macOS compositor to draw shadows beyond content bounds
        contentView?.wantsLayer = true
        contentView?.layer?.masksToBounds = false
    }
}
