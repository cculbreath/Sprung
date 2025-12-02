import SwiftUI
import SwiftyJSON

struct KnowledgeCardReviewCard: View {
    @Binding var card: KnowledgeCardDraft
    @State private var expandedSources: Set<UUID> = []
    let artifacts: [ArtifactRecord]
    let onApprove: (KnowledgeCardDraft) -> Void
    let onReject: (String) -> Void

    init(
        card: Binding<KnowledgeCardDraft>,
        artifacts: [ArtifactRecord],
        onApprove: @escaping (KnowledgeCardDraft) -> Void,
        onReject: @escaping (String) -> Void
    ) {
        _card = card
        self.artifacts = artifacts
        self.onApprove = onApprove
        self.onReject = onReject
    }

    var body: some View {
        ValidationCardContainer(
            draft: $card,
            originalDraft: card,
            title: "Review Knowledge Card",
            onSave: { draft in
                await MainActor.run {
                    onApprove(draft)
                }
                return true
            },
            onCancel: {
                onReject("User cancelled review")
            },
            content: { _ in
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    contentSection
                    sourcesSection
                }
            }
        )
    }

    private var headerSection: some View {
        SectionCard(title: card.title.isEmpty ? "Untitled Knowledge Card" : card.title) {
            VStack(alignment: .leading, spacing: 8) {
                // Metadata row
                HStack(spacing: 16) {
                    if let cardType = card.cardType {
                        Label(cardType.capitalized, systemImage: typeIcon(for: cardType))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let org = card.organization, !org.isEmpty {
                        Label(org, systemImage: "building.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let location = card.location, !location.isEmpty {
                        Label(location, systemImage: "location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let timePeriod = card.timePeriod, !timePeriod.isEmpty {
                    Label(timePeriod, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Word count indicator
                HStack {
                    let count = card.wordCount
                    let color: Color = count < 500 ? .orange : (count >= 500 ? .green : .primary)
                    Label("\(count) words", systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(color)
                    if count < 500 {
                        Text("(minimum 500 recommended)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var contentSection: some View {
        SectionCard(title: "Summary") {
            if card.content.isEmpty {
                Text("No content provided.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(card.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 400)
            }
        }
    }

    private var sourcesSection: some View {
        SectionCard(title: "Sources (\(card.sources.count))") {
            if card.sources.isEmpty {
                Text("No sources linked.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(card.sources) { source in
                        sourceRow(source)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: KnowledgeCardSource) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: source.type == "artifact" ? "doc.fill" : "bubble.left.fill")
                    .foregroundStyle(source.type == "artifact" ? .blue : .green)

                if source.type == "artifact" {
                    // Show artifact filename if we can find it
                    if let artifactId = source.artifactId,
                       let artifact = artifacts.first(where: { $0.id == artifactId }) {
                        Text(artifact.filename)
                            .font(.callout)
                    } else {
                        Text("Artifact: \(source.artifactId ?? "unknown")")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Chat excerpt")
                        .font(.callout)
                }

                Spacer()

                if source.type == "chat" {
                    Button(action: {
                        expandedSources.toggleMembership(of: source.id)
                    }) {
                        Image(systemName: expandedSources.contains(source.id) ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Show chat excerpt when expanded
            if source.type == "chat" && expandedSources.contains(source.id) {
                VStack(alignment: .leading, spacing: 4) {
                    if let excerpt = source.chatExcerpt {
                        Text("\"\(excerpt)\"")
                            .font(.callout)
                            .italic()
                            .foregroundStyle(.secondary)
                            .padding(.leading, 24)
                    }
                    if let context = source.chatContext {
                        Text(context)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 24)
                    }
                }
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 4)
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

private extension Set where Element: Hashable {
    mutating func toggleMembership(of element: Element) {
        if contains(element) {
            remove(element)
        } else {
            insert(element)
        }
    }
}
