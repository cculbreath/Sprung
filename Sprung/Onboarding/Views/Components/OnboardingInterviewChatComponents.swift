import SwiftUI
import SwiftyJSON

struct MessageBubble: View {
    let message: OnboardingMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(displayText)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundStyle(.primary)
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

    private var displayText: String {
        switch message.role {
        case .assistant:
            return parseAssistantReply(from: message.text)
        case .user, .system:
            return message.text
        }
    }

    private func parseAssistantReply(from text: String) -> String {
        if let data = text.data(using: .utf8),
           let json = try? JSON(data: data),
           let reply = json["assistant_reply"].string {
            return reply
        }
        if let range = text.range(of: "\"assistant_reply\":") {
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

struct LLMActivityView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let value = sin(time * 1.6)
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 8)
                AngularGradient(
                    gradient: Gradient(colors: [.accentColor, .purple, .pink, .accentColor]),
                    center: .center,
                    angle: .degrees(value * 180)
                )
                .mask(
                    Circle()
                        .trim(from: 0.0, to: 0.75)
                        .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                )
                .rotationEffect(.degrees(value * 120))
            }
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: value)
        }
    }
}
