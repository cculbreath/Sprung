import SwiftUI
import SwiftyJSON

/// Row view for displaying an artifact with expand/collapse, demote, and delete actions.
/// Shows artifact content, metadata, and git analysis when expanded.
///
/// Delegates rendering to focused sub-views:
/// - `ArtifactRowHeader` (always-visible collapsed header)
/// - `ArtifactPendingSkillsSection` (editable pending skills)
/// - `ArtifactSkillsSection` (read-only approved skills)
/// - `ArtifactNarrativeCardsSection` (knowledge cards)
/// - `ArtifactGitAnalysisSection` (git repo analysis)
struct ArtifactRow: View {
    let artifact: ArtifactRecord
    let isExpanded: Bool
    let pendingSkills: [Skill]
    let onToggleExpand: () -> Void
    let onDemote: () -> Void
    let onDelete: () -> Void
    let onDeleteSkill: ((Skill) -> Void)?
    let onRegenSkills: (() -> Void)?
    let onRegenNarrativeCards: (() -> Void)?

    init(
        artifact: ArtifactRecord,
        isExpanded: Bool,
        pendingSkills: [Skill] = [],
        onToggleExpand: @escaping () -> Void,
        onDemote: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onDeleteSkill: ((Skill) -> Void)? = nil,
        onRegenSkills: (() -> Void)? = nil,
        onRegenNarrativeCards: (() -> Void)? = nil
    ) {
        self.artifact = artifact
        self.isExpanded = isExpanded
        self.pendingSkills = pendingSkills
        self.onToggleExpand = onToggleExpand
        self.onDemote = onDemote
        self.onDelete = onDelete
        self.onDeleteSkill = onDeleteSkill
        self.onRegenSkills = onRegenSkills
        self.onRegenNarrativeCards = onRegenNarrativeCards
    }

    private var hasContent: Bool {
        !artifact.extractedContent.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            ArtifactRowHeader(
                artifact: artifact,
                isExpanded: isExpanded,
                onToggleExpand: onToggleExpand,
                onDemote: onDemote,
                onDelete: onDelete
            )

            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 8) {
                    // Brief description (if available)
                    if let briefDesc = artifact.briefDescription, !briefDesc.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "text.quote")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(briefDesc)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .italic()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(6)
                    }

                    // Summary section (if available)
                    if let summary = artifact.summary, !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Summary")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("~\(formatTokenCount(artifact.summaryTokens)) tokens")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.purple.opacity(0.08))
                                .cornerRadius(6)
                        }
                    }

                    // Pending skills section (from SkillStore, with delete buttons)
                    if !pendingSkills.isEmpty {
                        ArtifactPendingSkillsSection(
                            skills: pendingSkills,
                            onDeleteSkill: onDeleteSkill ?? { _ in }
                        )
                    }

                    // Extracted skills section (from artifact JSON, read-only)
                    if let skills = artifact.skills, !skills.isEmpty, pendingSkills.isEmpty {
                        ArtifactSkillsSection(
                            skills: skills,
                            onRegenSkills: onRegenSkills
                        )
                    }

                    // Narrative cards section (if available)
                    if let narrativeCards = artifact.narrativeCards, !narrativeCards.isEmpty {
                        ArtifactNarrativeCardsSection(
                            cards: narrativeCards,
                            onRegenNarrativeCards: onRegenNarrativeCards
                        )
                    }

                    if hasContent {
                        // Content section - truncate to prevent UI hang on large documents
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Extracted Content")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("~\(formatTokenCount(artifact.extractedContentTokens)) tokens")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            let previewLimit = 10_000
                            let contentPreview = artifact.extractedContent.count > previewLimit
                                ? String(artifact.extractedContent.prefix(previewLimit)) + "\n\n[... truncated for display - \(artifact.extractedContent.count - previewLimit) more characters ...]"
                                : artifact.extractedContent

                            ScrollView {
                                Text(contentPreview)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 200)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                        }
                    } else if artifact.summary == nil {
                        // No content yet (only show if no summary either)
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                            Text("Content not yet extracted")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }

                    // Metadata section (if available)
                    if !artifact.metadata.isEmpty {
                        metadataSection
                    }
                }
                .padding(10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isExpanded ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor), lineWidth: isExpanded ? 1.5 : 1)
        )
    }

    // MARK: - Metadata

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Metadata")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                // Show basic metadata fields
                if let purpose = artifact.metadata["purpose"].string {
                    metadataRow(label: "Purpose", value: purpose)
                }
                if let title = artifact.metadata["title"].string {
                    metadataRow(label: "Title", value: title)
                }
                if let sha = artifact.sha256 {
                    metadataRow(label: "SHA256", value: String(sha.prefix(16)) + "...")
                }

                // Show git analysis if present
                if let analysis = artifact.metadata["analysis"].dictionary, !analysis.isEmpty {
                    ArtifactGitAnalysisSection(analysis: artifact.metadata["analysis"])
                }

                // Show full JSON for debugging/inspection
                DisclosureGroup {
                    ScrollView {
                        Text(artifact.metadata.rawString(options: [.prettyPrinted, .sortedKeys]) ?? "{}")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)
                } label: {
                    Text("Raw JSON")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(6)
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Formatting Helpers

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
}
