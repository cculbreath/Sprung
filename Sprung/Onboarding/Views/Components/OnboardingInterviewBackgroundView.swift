import SwiftUI

struct OnboardingInterviewBackgroundView: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(
                colors: [
                    Color.white.opacity(0.9),
                    Color.white.opacity(0.95),
                    Color.white.opacity(0.9)
                ]
            ),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
