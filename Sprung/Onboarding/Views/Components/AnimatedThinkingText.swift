import SwiftUI
/// Animated busy indicator with custom Sprung icon and optional status text
struct AnimatedThinkingText: View {
    let statusMessage: String?
    init(statusMessage: String? = nil) {
        self.statusMessage = statusMessage
    }
    var body: some View {
        VStack(spacing: 16) {
            animatedSparklesIcon
            if let statusMessage = statusMessage {
                statusText(statusMessage)
            }
        }
    }
    private var animatedSparklesIcon: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let bounce = sin(time * 3) * 0.05 + 1.0  // Gentle bounce
            let wiggle = sin(time * 5) * 3  // Wiggle rotation
            let breathe = sin(time * 2) * 0.1 + 1.0  // Breathing scale
            Image("custom.sprung_raster")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .scaleEffect(bounce * breathe)
                .rotationEffect(.degrees(wiggle))
                .offset(y: sin(time * 4) * 2)  // Subtle vertical float
        }
    }
    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .modifier(ShimmerModifier())
            .frame(maxWidth: 280)
    }
}
/// Shimmer animation modifier for text
struct ShimmerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    TimelineView(.animation(minimumInterval: 1/60)) { timeline in
                        let width = geometry.size.width
                        let height = geometry.size.height
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let duration: Double = 2.0
                        let progress = (time.truncatingRemainder(dividingBy: duration)) / duration
                        let offset = (progress * 2.0 - 0.5) * width * 1.5
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.5),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.3, height: height * 2)
                        .offset(x: offset)
                        .blendMode(.overlay)
                        .allowsHitTesting(false)
                    }
                }
                .mask(content)
            )
    }
}
