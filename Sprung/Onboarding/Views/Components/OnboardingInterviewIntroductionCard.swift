import SwiftUI
struct OnboardingInterviewIntroductionCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateIn = false

    private let highlights: [(systemImage: String, text: String)] = [
        ("person.text.rectangle", "Confirm contact info from a résumé, LinkedIn, macOS Contacts, or manual entry."),
        ("list.number", "Choose the JSON Resume sections that describe your experience."),
        ("tray.full", "Review every section entry before it’s saved to your profile.")
    ]

    var body: some View {
        VStack(spacing: 28) {
            Image("custom.onboardinginterview")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(.accentColor)
                .scaledToFit()
                .frame(width: 160, height: 160)
                .opacity(animateIn ? 1 : 0)
                .scaleEffect(animateIn ? 1 : 0.62)
                .rotationEffect(.degrees(animateIn ? 0 : -10))
                .offset(y: animateIn ? 0 : -22)
                .blur(radius: animateIn ? 0 : 10)
                .animation(
                    .interpolatingSpring(stiffness: 280, damping: 14).delay(0.06),
                    value: animateIn
                )
            VStack(spacing: 8) {
                Text("Welcome to Sprung!")
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .multilineTextAlignment(.center)
                    .opacity(animateIn ? 1 : 0)
                    .scaleEffect(animateIn ? 1 : 0.90)
                    .offset(y: animateIn ? 0 : -10)
                    .blur(radius: animateIn ? 0 : 8)
                    .animation(
                        .interpolatingSpring(stiffness: 260, damping: 18).delay(0.14),
                        value: animateIn
                    )
                Text("We’ll confirm your contact details, enable the right résumé sections, and collect highlights so Sprung can advocate for you.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .opacity(animateIn ? 1 : 0)
                    .scaleEffect(animateIn ? 1 : 0.96)
                    .offset(y: animateIn ? 0 : -6)
                    .blur(radius: animateIn ? 0 : 8)
                    .animation(
                        .interpolatingSpring(stiffness: 220, damping: 20).delay(0.20),
                        value: animateIn
                    )
            }
            OnboardingInterviewHighlights(
                highlights: highlights,
                animateIn: animateIn
            )
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 25)
        .onAppear {
            if reduceMotion {
                animateIn = true
                return
            }
            animateIn = true
        }
        .onDisappear {
            animateIn = false
        }
    }
}
private struct OnboardingInterviewHighlights: View {
    let highlights: [(systemImage: String, text: String)]
    let animateIn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Part 1 Goals")
                .font(.headline)
                .foregroundStyle(.primary)
                .opacity(animateIn ? 1 : 0)
                .scaleEffect(animateIn ? 1 : 0.94, anchor: .leading)
                .offset(x: animateIn ? 0 : -12, y: animateIn ? 0 : 4)
                .blur(radius: animateIn ? 0 : 6)
                .animation(
                    .interpolatingSpring(stiffness: 240, damping: 20).delay(0.28),
                    value: animateIn
                )
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(highlights.enumerated()), id: \.offset) { index, item in
                    highlightRow(
                        systemImage: item.systemImage,
                        text: item.text
                    )
                    .opacity(animateIn ? 1 : 0)
                    .scaleEffect(animateIn ? 1 : 0.96, anchor: .leading)
                    .offset(x: animateIn ? 0 : -18, y: animateIn ? 0 : 10)
                    .blur(radius: animateIn ? 0 : 8)
                    .animation(
                        .interpolatingSpring(stiffness: 240, damping: 20)
                            .delay(0.34 + (Double(index) * 0.08)),
                        value: animateIn
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func highlightRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.body)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
