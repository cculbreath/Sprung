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
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            animatedSparklesIcon
            animatedPhrase
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPhraseIndex = (currentPhraseIndex + 1) % phrases.count
            }
        }
    }

    private var animatedSparklesIcon: some View {
        Image("custom.sprung_outline")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .frame(width: 48, height: 48)
            .foregroundStyle(rainbowGradient)
            .scaleEffect(thinking ? 1.05 : 0.95)
            .animation(
                .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true),
                value: thinking
            )
    }

    private var animatedPhrase: some View {
        HStack(spacing: 0) {
            ForEach(Array(phrases[currentPhraseIndex].enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .font(.title3)
                    .foregroundStyle(rainbowGradient)
                    .opacity(thinking ? 0.6 : 0.9)
                    .scaleEffect(thinking ? 0.95 : 1, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.05),
                        value: thinking
                    )
            }
        }
    }

    private var rainbowGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0, green: 0.8, blue: 1.0),        // #0CF
                Color(red: 0.46, green: 0.30, blue: 1.0),    // #764DFF
                Color(red: 0.69, green: 0, blue: 0.41),      // #B00068
                Color(red: 0.94, green: 0.17, blue: 0)       // #F02C00
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    AnimatedThinkingText()
        .preferredColorScheme(.dark)
        .padding()
}
