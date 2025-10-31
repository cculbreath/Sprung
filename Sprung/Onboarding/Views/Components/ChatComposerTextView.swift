import AppKit
import SwiftUI

struct ChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = ChatNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = NSColor.controlBackgroundColor
        let coordinator = context.coordinator
        textView.onReturn = { [weak coordinator] in
            coordinator?.submit()
        }
        textView.string = text
        textView.isEditable = isEditable
        textView.isSelectable = isEditable
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false

        scrollView.documentView = textView
        coordinator.parent = self
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            textView.string = text
            textView.scrollToEndOfDocument(nil)
        }

        textView.isEditable = isEditable
        textView.isSelectable = isEditable
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatComposerTextView
        weak var textView: ChatNSTextView?

        init(parent: ChatComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
        }

        func submit() {
            parent.onSubmit(parent.text)
        }

        func invalidate() {
            textView?.delegate = nil
            textView?.onReturn = nil
        }
    }
}

final class ChatNSTextView: NSTextView {
    var onReturn: (() -> Void)?

    override func insertNewline(_ sender: Any?) {
        if let event = window?.currentEvent,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
            super.insertNewline(sender)
        } else {
            onReturn?()
        }
    }
}
