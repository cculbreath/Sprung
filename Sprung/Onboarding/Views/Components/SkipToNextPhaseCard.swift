import SwiftUI

struct SkipToNextPhaseCard: View {
    let currentPhase: InterviewPhase
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "forward.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Ready to move on?")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(nextPhaseDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onSkip) {
                HStack {
                    Text("Skip to \(nextPhaseName)")
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var nextPhaseName: String {
        switch currentPhase {
        case .phase1VoiceContext:
            return "Career Story"
        case .phase2CareerStory:
            return "Evidence Collection"
        case .phase3EvidenceCollection:
            return "Strategic Synthesis"
        case .phase4StrategicSynthesis:
            return "Complete Interview"
        case .complete:
            return "Complete"
        }
    }

    private var nextPhaseDescription: String {
        switch currentPhase {
        case .phase1VoiceContext:
            return "Next: Map out your career timeline from your resume or through conversation."
        case .phase2CareerStory:
            return "Next: Upload documents, code repos, and other evidence to support your experience."
        case .phase3EvidenceCollection:
            return "Next: Synthesize your strengths, identify pitfalls, and finalize your candidate dossier."
        case .phase4StrategicSynthesis:
            return "Finish the interview and start building resumes and applications."
        case .complete:
            return "Interview complete."
        }
    }
}
