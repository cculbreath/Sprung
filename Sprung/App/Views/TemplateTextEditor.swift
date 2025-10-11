//
//  TemplateTextEditor.swift
//  Sprung
//
//  Custom text editor with native macOS find functionality
//

import SwiftUI
import AppKit

struct TemplateTextEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    var onTextChange: (() -> Void)?
    
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
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TemplateTextEditor
        
        init(_ parent: TemplateTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onTextChange?()
        }
    }
}
