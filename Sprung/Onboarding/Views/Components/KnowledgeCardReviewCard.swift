import SwiftUI
import SwiftyJSON

struct KnowledgeCardReviewCard: View {
    @Binding var card: KnowledgeCardDraft

    @State private var expandedCitations: Set<UUID> = []
    @State private var rejectedClaims: Set<UUID> = []

    let artifacts: [ArtifactRecord]
    let onApprove: (KnowledgeCardDraft) -> Void
    let onReject: (Set<UUID>, String) -> Void

    init(
        card: Binding<KnowledgeCardDraft>,
        artifacts: [ArtifactRecord],
        onApprove: @escaping (KnowledgeCardDraft) -> Void,
        onReject: @escaping (Set<UUID>, String) -> Void
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
                let filtered = draft.removing(claims: rejectedClaims)
                await MainActor.run {
                    onApprove(filtered)
                    rejectedClaims.removeAll()
                }
                return true
            },
            onCancel: {
                onReject(rejectedClaims, "User cancelled review")
                rejectedClaims.removeAll()
            },
            content: { callbacks in
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    achievementsSection(callbacks)
                    evidenceSection
                    metricsSection
                }
            }
        )
    }

    private var headerSection: some View {
        SectionCard(title: card.title.isEmpty ? "Untitled Knowledge Card" : card.title) {
            VStack(alignment: .leading, spacing: 12) {
                if !card.summary.isEmpty {
                    Text(card.summary)
                        .font(.body)
                }

                if let source = card.source, !source.isEmpty {
                    Label(source, systemImage: "book")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !card.skills.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Skills")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(card.skills.joined(separator: ", "))
                            .font(.callout)
                    }
                }
            }
        }
    }

    private func achievementsSection(_ callbacks: EditableContentCallbacks) -> some View {
        SectionCard(title: "Achievements") {
            if card.achievements.isEmpty {
                Text("No achievements provided.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(card.achievements) { achievement in
                    CitationRow(
                        claim: achievement.claim,
                        evidence: achievement.evidence,
                        isExpanded: expandedCitations.contains(achievement.id),
                        isRejected: rejectedClaims.contains(achievement.id),
                        onToggleExpand: {
                            expandedCitations.toggleMembership(of: achievement.id)
                        },
                        onToggleReject: {
                            rejectedClaims.toggleMembership(of: achievement.id)
                            callbacks.onChange()
                        }
                    )
                    .animation(.default, value: expandedCitations)
                }
            }
        }
    }

    private var evidenceSection: some View {
        SectionCard(title: "Evidence Attachments") {
            if artifacts.isEmpty {
                Text("No supporting artifacts captured yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(artifacts) { artifact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artifact.filename)
                            .font(.callout)
                        let size = byteCountFormatter.string(fromByteCount: Int64(artifact.sizeInBytes))
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let purpose = artifact.metadata["purpose"].string {
                            Text("Purpose: \(purpose)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var metricsSection: some View {
        SectionCard(title: "Metrics") {
            if card.metrics.isEmpty {
                Text("No quantified impact recorded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(card.metrics, id: \.self) { metric in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.seal")
                                .foregroundStyle(.green)
                            Text(metric)
                                .font(.callout)
                        }
                    }
                }
            }
        }
    }

    private var byteCountFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter
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
