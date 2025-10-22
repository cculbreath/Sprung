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
    private let gradientColors: [Color] = [
        Color(red: 1.0, green: 0.58, blue: 0.2),
        Color(red: 0.98, green: 0.32, blue: 0.62),
        Color(red: 0.62, green: 0.35, blue: 0.95),
        Color(red: 0.15, green: 0.65, blue: 0.97)
    ]

    private let rotationDuration: Double = 1.2

    var body: some View {
        TimelineView(.animation) { timeline in
            let timestamp = timeline.date.timeIntervalSinceReferenceDate
            let progress = (timestamp.truncatingRemainder(dividingBy: rotationDuration)) / rotationDuration
            spinner
                .rotationEffect(.degrees(progress * 360))
        }
        .frame(width: 44, height: 44)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var spinner: some View {
        let gradient = AngularGradient(
            gradient: Gradient(colors: gradientColors + [gradientColors.first ?? .accentColor]),
            center: .center
        )

        return ZStack {
            Circle()
                .fill(gradient)

            Circle()
                .fill(gradient)
                .blur(radius: 8)
                .opacity(0.85)

            Circle()
                .fill(gradient)
                .blur(radius: 18)
                .opacity(0.65)

            Circle()
                .fill(gradient)
                .blur(radius: 38)
                .opacity(0.35)

            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .padding(14)

            Circle()
                .strokeBorder(Color.white.opacity(0.7), lineWidth: 4)
                .padding(10)
        }
        .compositingGroup()
        .shadow(color: gradientColors.last?.opacity(0.35) ?? .clear, radius: 22, y: 12)
    }
}
