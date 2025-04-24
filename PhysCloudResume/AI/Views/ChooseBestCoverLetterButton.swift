import SwiftUI

/// Button for choosing the best cover letter via AI recommendation.
struct ChooseBestCoverLetterButton: View {
    @Binding var cL: CoverLetter
    @Binding var buttons: CoverLetterButtons
    let action: () -> Void
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    var body: some View {
        if buttons.chooseBestRequested {
            ProgressView()
                .scaleEffect(0.75, anchor: .center)
                .frame(width: 36, height: 36)
        } else {
            Button(action: action) {
                Image(systemName: "medal")
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(
                jobAppStore.selectedApp?.coverLetters.count ?? 0 <= 1
                    || cL.writingSamplesString.isEmpty
            )
            .help(
                (jobAppStore.selectedApp?.coverLetters.count ?? 0) <= 1
                    ? "At least two cover letters are required"
                    : cL.writingSamplesString.isEmpty
                    ? "Add writing samples to enable choosing best cover letter"
                    : "Select the best cover letter based on style and voice"
            )
        }
    }
}
