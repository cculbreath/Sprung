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
        Color(red: 1.0, green: 0.38, blue: 0.0),
        Color(red: 0.95, green: 0.15, blue: 0.55),
        Color(red: 0.56, green: 0.17, blue: 0.95),
        Color(red: 0.0, green: 0.54, blue: 0.98)
    ]

    private let rotationDuration: Double = 1.2

    var body: some View {
        TimelineView(.animation) { timeline in
            let timestamp = timeline.date.timeIntervalSinceReferenceDate
            let progress = (timestamp.truncatingRemainder(dividingBy: rotationDuration)) / rotationDuration
            spinner
                .rotationEffect(.degrees(progress * 360))
        }
        .frame(width: 48, height: 48)
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
                .stroke(gradient, lineWidth: 22)

            Circle()
                .stroke(gradient, lineWidth: 22)
                .blur(radius: 10)
                .opacity(0.9)

            Circle()
                .stroke(gradient, lineWidth: 22)
                .blur(radius: 26)
                .opacity(0.7)

            Circle()
                .stroke(gradient, lineWidth: 22)
                .blur(radius: 44)
                .opacity(0.45)

            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .padding(18)

            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 4)
                .padding(16)
        }
        .saturation(1.4)
        .brightness(0.05)
        .shadow(color: gradientColors.first?.opacity(0.4) ?? .clear, radius: 26, y: 14)
        .shadow(color: gradientColors.last?.opacity(0.3) ?? .clear, radius: 20, y: -8)
    }
}
