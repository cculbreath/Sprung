import AppKit
import SwiftUI
import SwiftyJSON

struct JsonValidatingTextEditor: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    @Binding var sourceContent: String
    @Binding var isValidJSON: Bool

    func makeNSView(context: Context) -> NSScrollView {
        print("📝 makeNSView called") // Debug log

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

        // Set up scroll view
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != sourceContent {
            print("📝 updateNSView: Content changed externally") // Debug log
            textView.string = sourceContent
            context.coordinator.validateJSON(sourceContent)
        }
    }

    func makeCoordinator() -> Coordinator {
        print("📝 makeCoordinator called") // Debug log
        return Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JsonValidatingTextEditor
        private var validationWorkItem: DispatchWorkItem?

        init(_ parent: JsonValidatingTextEditor) {
            self.parent = parent
            super.init()
            print("📝 Coordinator initialized") // Debug log
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string

            print("📝 textDidChange triggered") // Debug log

            // Update source content immediately
            DispatchQueue.main.async {
                self.parent.sourceContent = newText
            }

            // Cancel any pending validation
            validationWorkItem?.cancel()

            // Create new validation task
            let workItem = DispatchWorkItem { [weak self] in
                print("📝 Validation work item executing") // Debug log
                self?.validateJSON(newText)
            }

            validationWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }

        func validateJSON(_ text: String) {
            print("📝 validateJSON called with text: \(text.prefix(50))...") // Debug log

            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                print("📝 Empty text - considering valid") // Debug log
                DispatchQueue.main.async {
                    self.parent.isValidJSON = true
                }
                return
            }

            do {
                if let jsonData = text.data(using: .utf8) {
                    _ = try JSON(data: jsonData)
                    print("📝 JSON is valid") // Debug log
                    DispatchQueue.main.async {
                        self.parent.isValidJSON = true
                    }
                } else {
                    print("📝 Failed to convert to data") // Debug log
                    DispatchQueue.main.async {
                        self.parent.isValidJSON = false
                    }
                }
            } catch {
                print("📝 JSON validation error: \(error)") // Debug log
                DispatchQueue.main.async {
                    self.parent.isValidJSON = false
                }
            }
        }
    }
}
