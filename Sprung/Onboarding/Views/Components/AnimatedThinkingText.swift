import SwiftUI

/// Animated thinking text component inspired by Apple Intelligence style
/// Shows sparkles icon with breathing animation and animated text
struct AnimatedThinkingText: View {
    @State private var thinking = true

    private let phrases = [
        "Thinking",
        "Analyzing",
        "Processing"
    ]

    @State private var currentPhraseIndex = 0
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            animatedSparklesIcon
            animatedPhrase
        }
        .onReceive(timer) { _ in
            withAnimation {
                currentPhraseIndex = (currentPhraseIndex + 1) % phrases.count
            }
        }
        .onAppear {
            thinking = true
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
                .frame(width: 48, height: 48)
                .scaleEffect(bounce * breathe)
                .rotationEffect(.degrees(wiggle))
                .offset(y: sin(time * 4) * 2)  // Subtle vertical float
        }
    }

    private var animatedPhrase: some View {
        HStack(spacing: 0) {
            ForEach(Array(phrases[currentPhraseIndex].enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color(red: 0, green: 0.169, blue: 0.776))
                    .hueRotation(.degrees(thinking ? 220 : 0))
                    .opacity(thinking ? 1 : 0)  // Inverted - visible when thinking
                    .scaleEffect(x: thinking ? 0.85 : 1, y: thinking ? 1.15 : 1, anchor: .bottom)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .delay(1)
                            .repeatForever(autoreverses: true)  // Changed to autoreverses for pulsing effect
                            .delay(Double(index) * 0.08),  // Staggered wave
                        value: thinking
                    )
            }
        }
    }
}

#Preview {
    AnimatedThinkingText()
        .preferredColorScheme(.dark)
        .padding()
}
