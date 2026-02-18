//
//  OnboardingWindowAnimator.swift
//  Sprung
//
//  Presents the onboarding interview window with a spring-in animation
//  (scale + fade + overshoot). Falls back to instant presentation when
//  Reduce Motion is enabled.
//
import Cocoa
import QuartzCore

@MainActor
enum OnboardingWindowAnimator {
    static func present(_ window: NSWindow) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.alphaValue = 1
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let finalFrame = window.frame
        let minHeight = window.minSize.height

        func frame(height: CGFloat, yOffset: CGFloat) -> NSRect {
            var next = finalFrame
            next.size.height = height
            let heightDelta = height - finalFrame.size.height
            next.origin.y = finalFrame.origin.y - (heightDelta / 2) + yOffset
            return next
        }

        let startHeight = max(finalFrame.size.height * 0.90, minHeight)
        let overshootHeight = max(finalFrame.size.height * 1.02, minHeight)
        let undershootHeight = max(finalFrame.size.height * 0.995, minHeight)

        let startFrame = frame(height: startHeight, yOffset: -120)
        let overshootFrame = frame(height: overshootHeight, yOffset: 18)
        let undershootFrame = frame(height: undershootHeight, yOffset: -6)

        window.alphaValue = 0
        window.setFrame(startFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(overshootFrame, display: true)
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(undershootFrame, display: true)
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(finalFrame, display: true)
                }
            }
        }
    }
}
