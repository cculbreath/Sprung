import SwiftUI
import SwiftyJSON
struct MessageBubble: View {
    let message: OnboardingMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                bubbleContent
                    .background(backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520, alignment: message.role == .user ? .trailing : .leading)
            if message.role != .user { Spacer() }
        }
        .transition(.opacity)
    }
    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor.opacity(0.2)
        case .assistant:
            return Color(nsColor: .controlBackgroundColor)
        case .system:
            return Color.gray.opacity(0.15)
        }
    }
    private var bubbleContent: some View {
        let alignment: Alignment = message.role == .user ? .trailing : .leading
        let multilineAlignment: TextAlignment = message.role == .user ? .trailing : .leading
        return VStack(alignment: .leading, spacing: 8) {
            Text(markdownAttributedString)
                .multilineTextAlignment(multilineAlignment)
            // Reasoning summaries now display in dedicated sidebar (ChatGPT-style)
        }
        .frame(
            maxWidth: .infinity,
            alignment: alignment
        )
        .padding(12)
        .foregroundStyle(.primary)
    }

    /// Parses the display text as markdown, falling back to plain text on failure
    private var markdownAttributedString: AttributedString {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            return try AttributedString(markdown: displayText, options: options)
        } catch {
            // Fall back to plain text if markdown parsing fails
            return AttributedString(displayText)
        }
    }
    private var displayText: String {
        switch message.role {
        case .assistant:
            return parseAssistantReply(from: message.text)
        case .user:
            return stripChatboxTags(from: message.text)
        case .system:
            return message.text
        }
    }
    private func stripChatboxTags(from text: String) -> String {
        // Remove <chatbox> and </chatbox> tags that are added for LLM context
        // Also handle HTML-encoded versions in case they were encoded somewhere
        let stripped = text
            .replacingOccurrences(of: "<chatbox>", with: "")
            .replacingOccurrences(of: "</chatbox>", with: "")
            .replacingOccurrences(of: "&lt;chatbox&gt;", with: "")
            .replacingOccurrences(of: "&lt;/chatbox&gt;", with: "")
        // Debug logging to help diagnose the issue
        if text != stripped {
            Logger.debug("🏷️ Stripped chatbox tags from: '\(text.prefix(100))'", category: .ai)
        } else if text.contains("chatbox") {
            Logger.warning("⚠️ Text contains 'chatbox' but wasn't stripped: '\(text.prefix(100))'", category: .ai)
        }
        return stripped
    }
    private func parseAssistantReply(from text: String) -> String {
        if let data = text.data(using: .utf8),
           let json = try? JSON(data: data),
           let reply = json["assistantReply"].string {
            return reply
        }
        if let range = text.range(of: "\"assistantReply\":") {
            let substring = text[range.upperBound...]
            if let closingQuote = substring.firstIndex(of: "\"") {
                let trimmed = substring[closingQuote...].dropFirst()
                if let end = trimmed.firstIndex(of: "\"") {
                    return String(trimmed[..<end])
                }
            }
        }
        return text
    }
}
