//
//  JsonValidatingTextEditor.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

import AppKit
import SwiftUI
import SwiftyJSON

struct JsonValidatingTextEditor: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    @Binding var sourceContent: String
    @Binding var isValidJSON: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

        // Set initial content and validate
        textView.string = sourceContent
        context.coordinator.validateJSON(sourceContent) // Initial validation

        // Configure text container
        let textContainer = textView.textContainer!
        textContainer.containerSize = NSSize(width: scrollView.frame.width, height: CGFloat.greatestFiniteMagnitude)
        textContainer.widthTracksTextView = true

        // Configure layout
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        // Enable editing
        textView.isEditable = true
        textView.isSelectable = true
        
        // Disable autocorrect and smart quotes for JSON editing
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        // Set up scroll view
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != sourceContent {
            textView.string = sourceContent
            context.coordinator.validateJSON(sourceContent)
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JsonValidatingTextEditor
        private var validationWorkItem: DispatchWorkItem?

        init(_ parent: JsonValidatingTextEditor) {
            self.parent = parent
            super.init()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string

            // Update source content immediately
            DispatchQueue.main.async {
                self.parent.sourceContent = newText
            }

            // Cancel any pending validation
            validationWorkItem?.cancel()

            // Create new validation task
            let workItem = DispatchWorkItem { [weak self] in
                self?.validateJSON(newText)
            }

            validationWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }

        func validateJSON(_ text: String) {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                DispatchQueue.main.async {
                    self.parent.isValidJSON = true
                }
                return
            }

            do {
                if let jsonData = text.data(using: .utf8) {
                    _ = try JSON(data: jsonData)
                    DispatchQueue.main.async {
                        self.parent.isValidJSON = true
                    }
                } else {
                    DispatchQueue.main.async {
                        self.parent.isValidJSON = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.parent.isValidJSON = false
                }
            }
        }
    }
}
