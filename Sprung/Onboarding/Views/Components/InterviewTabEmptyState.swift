import SwiftUI

struct InterviewTabEmptyState: View {
    let phase: InterviewPhase

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var icon: String {
        switch phase {
        case .phase1VoiceContext:
            return "person.text.rectangle"
        case .phase2CareerStory:
            return "doc.badge.plus"
        case .phase3EvidenceCollection:
            return "text.document"
        case .phase4StrategicSynthesis:
            return "chart.bar.doc.horizontal"
        case .complete:
            return "checkmark.circle"
        }
    }

    private var title: String {
        switch phase {
        case .phase1VoiceContext:
            return "Building Your Profile"
        case .phase2CareerStory:
            return "Career Story"
        case .phase3EvidenceCollection:
            return "Evidence Collection"
        case .phase4StrategicSynthesis:
            return "Strategic Synthesis"
        case .complete:
            return "Interview Complete"
        }
    }

    private var message: String {
        switch phase {
        case .phase1VoiceContext:
            return "The AI is gathering information about your background. Interactive cards will appear here as the conversation progresses."
        case .phase2CareerStory:
            return "Building your career timeline. Add experience entries and enrich each with context."
        case .phase3EvidenceCollection:
            return "Upload documents, code repositories, and other evidence to support your experience."
        case .phase4StrategicSynthesis:
            return "Synthesizing your experience into strategic recommendations for your job search."
        case .complete:
            return "The interview has been completed. You can browse your collected data in the other tabs."
        }
    }
}
