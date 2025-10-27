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
        Image("custom.sprung_raster")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 48, height: 48)
            .scaleEffect(thinking ? 1.1 : 0.9)
            .rotationEffect(.degrees(thinking ? 5 : -5))
            .animation(
                .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: thinking
            )
    }

    private var animatedPhrase: some View {
        HStack(spacing: 0) {
            ForEach(Array(phrases[currentPhraseIndex].enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color(red: 0, green: 0.169, blue: 0.776))
                    .hueRotation(.degrees(thinking ? 220 : 0))
                    .opacity(thinking ? 0 : 1)
                    .scaleEffect(thinking ? 1.5 : 1, anchor: .bottom)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .delay(1)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) / 20),
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
