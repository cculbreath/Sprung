import SwiftUI

struct OnboardingInterviewBackgroundView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("custom.onboarding")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.45),
                        Color.black.opacity(0.35),
                        Color.black.opacity(0.25)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.overlay)
            }
            .ignoresSafeArea()
        }
    }
}
