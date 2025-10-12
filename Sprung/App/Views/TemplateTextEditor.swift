//
//  TemplateTextEditor.swift
//  Sprung
//
//  Custom text editor with native macOS find functionality
//

import SwiftUI
import AppKit

struct TextEditorInsertionRequest: Identifiable, Equatable {
    let id = UUID()
    let text: String

    static func == (lhs: TextEditorInsertionRequest, rhs: TextEditorInsertionRequest) -> Bool {
        lhs.id == rhs.id
    }
}

struct TemplateTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var insertionRequest: TextEditorInsertionRequest?
    let font: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    var onTextChange: (() -> Void)?

    init(
        text: Binding<String>,
        insertionRequest: Binding<TextEditorInsertionRequest?> = .constant(nil),
        onTextChange: (() -> Void)? = nil
    ) {
        _text = text
        _insertionRequest = insertionRequest
        self.onTextChange = onTextChange
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let textView = scrollView.documentView as? NSTextView {
            textView.delegate = context.coordinator
            textView.string = text
            textView.font = font
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isRichText = false
            textView.importsGraphics = false
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            // Enable find panel
            textView.usesFindPanel = true
            // Set up text container
            textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
            context.coordinator.textView = textView
        } else {
            Logger.error("TemplateTextEditor: Expected NSTextView documentView not found")
        }
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.textView = textView
        context.coordinator.handleInsertionRequest(insertionRequest)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TemplateTextEditor
        weak var textView: NSTextView?
        private var lastHandledRequestID: UUID?
        
        init(_ parent: TemplateTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onTextChange?()
        }

        func handleInsertionRequest(_ request: TextEditorInsertionRequest?) {
            guard let request, lastHandledRequestID != request.id else { return }
            guard let textView else { return }
            lastHandledRequestID = request.id

            let selectedRange = textView.selectedRange()
            textView.insertText(request.text, replacementRange: selectedRange)
            parent.text = textView.string
            parent.onTextChange?()

            DispatchQueue.main.async {
                if self.parent.insertionRequest?.id == request.id {
                    self.parent.insertionRequest = nil
                }
            }
        }
    }
}
