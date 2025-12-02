import SwiftUI
import SwiftyJSON
struct DraftKnowledgeListView: View {
    let coordinator: OnboardingInterviewCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Draft Knowledge Cards")
                .font(.headline)
                .foregroundStyle(.secondary)
            if coordinator.ui.drafts.isEmpty {
                ContentUnavailableView(
                    "No Drafts Yet",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Drafts will appear here as evidence is processed.")
                )
                .frame(height: 150)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(coordinator.ui.drafts) { draft in
                            DraftKnowledgeCardRow(draft: draft)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
struct DraftKnowledgeCardRow: View {
    let draft: KnowledgeCardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(draft.title)
                    .font(.headline)
                Spacer()
                Text("Draft")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .foregroundStyle(.orange)
                    .cornerRadius(4)
            }
            // Show content preview (first ~100 chars)
            if !draft.content.isEmpty {
                Text(contentPreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            // Metadata row
            HStack(spacing: 12) {
                if let cardType = draft.cardType {
                    Label(cardType.capitalized, systemImage: typeIcon(for: cardType))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let org = draft.organization, !org.isEmpty {
                    Label(org, systemImage: "building.2")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Label("\(draft.wordCount) words", systemImage: "doc.text")
                    .font(.caption2)
                    .foregroundStyle(draft.wordCount >= 500 ? .green : .orange)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var contentPreview: String {
        let trimmed = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 100 {
            return trimmed
        }
        return String(trimmed.prefix(100)) + "..."
    }

    private func typeIcon(for type: String) -> String {
        switch type.lowercased() {
        case "job": return "briefcase"
        case "skill": return "star"
        case "education": return "graduationcap"
        case "project": return "folder"
        default: return "doc"
        }
    }
}
