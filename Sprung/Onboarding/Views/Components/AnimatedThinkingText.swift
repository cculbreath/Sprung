import SwiftUI

/// Animated busy indicator with custom Sprung icon
struct AnimatedThinkingText: View {
    var body: some View {
        animatedSparklesIcon
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
}
