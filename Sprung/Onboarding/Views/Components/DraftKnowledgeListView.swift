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
            
            Text(draft.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            HStack {
                ForEach(draft.skills.prefix(3), id: \.self) { skill in
                    Text(skill)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                if draft.skills.count > 3 {
                    Text("+\(draft.skills.count - 3)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
}
