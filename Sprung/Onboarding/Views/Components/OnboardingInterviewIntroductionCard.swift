import SwiftUI

struct OnboardingInterviewIntroductionCard: View {
    var body: some View {
        VStack(spacing: 28) {
            Image("custom.onboardinginterview")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(.accentColor)
                .scaledToFit()
                .frame(width: 160, height: 160)

            VStack(spacing: 8) {
                Text("Welcome to Sprung Onboarding")
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .multilineTextAlignment(.center)
                Text("We’ll confirm your contact details, enable the right résumé sections, and collect highlights so Sprung can advocate for you.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            OnboardingInterviewHighlights()
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OnboardingInterviewHighlights: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Part 1 Goals")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 12) {
                highlightRow(
                    systemImage: "person.text.rectangle",
                    text: "Confirm contact info from a résumé, LinkedIn, macOS Contacts, or manual entry."
                )
                highlightRow(
                    systemImage: "list.number",
                    text: "Choose the JSON Resume sections that describe your experience."
                )
                highlightRow(
                    systemImage: "tray.full",
                    text: "Review every section entry before it’s saved to your profile."
                )
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
        }
    }
}
