import SwiftUI
import SwiftyJSON

/// Row view for displaying an artifact with expand/collapse, demote, and delete actions.
/// Shows artifact content, metadata, and git analysis when expanded.
struct ArtifactRow: View {
    let artifact: ArtifactRecord
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onDemote: () -> Void
    let onDelete: () -> Void

    private var hasContent: Bool {
        !artifact.extractedContent.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            HStack(spacing: 0) {
                Button(action: onToggleExpand) {
                    HStack(spacing: 10) {
                        fileIcon
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(artifact.displayName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)

                            HStack(spacing: 8) {
                                // Show filename if different from display name (title)
                                if artifact.title != nil && !artifact.filename.isEmpty {
                                    Text(artifact.filename)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else if let contentType = artifact.contentType {
                                    Text(contentType.components(separatedBy: "/").last ?? contentType)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                if artifact.sizeInBytes > 0 {
                                    Text(formatFileSize(artifact.sizeInBytes))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        Spacer()

                        // Status indicators
                        if hasContent {
                            if artifact.hasCardInventory {
                                // Content extracted AND inventory generated
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                    .help("Content extracted, inventory generated")
                            } else if artifact.isWritingSample {
                                // Writing samples don't need inventory - show success
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                    .help("Writing sample extracted")
                            } else {
                                // Content extracted but NO inventory yet
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                    .help("No card inventory generated")
                            }
                        }

                        // Graphics extraction status (PDFs only)
                        if artifact.isPDF {
                            if artifact.graphicsExtractionFailed {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                    .help("Graphics analysis failed: \(artifact.graphicsExtractionError ?? "Unknown error")")
                            } else if artifact.hasGraphicsContent {
                                Image(systemName: "photo.badge.checkmark")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                    .help("Visual content analyzed")
                            }
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Demote button (remove from interview, keep in archive)
                Button(action: onDemote) {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from interview (keep in archive)")

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete permanently")
            }

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

                    // Card inventory section (if available)
                    if let inventory = artifact.cardInventory, !inventory.proposedCards.isEmpty {
                        cardInventorySection(inventory)
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
                    gitAnalysisSection(analysis: artifact.metadata["analysis"])
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

    @ViewBuilder
    private func cardInventorySection(_ inventory: DocumentInventory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "rectangle.stack.badge.person.crop")
                    .foregroundStyle(.teal)
                Text("Card Inventory (\(inventory.proposedCards.count) cards)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(inventory.documentType.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.teal.opacity(0.15))
                    .foregroundStyle(.teal)
                    .cornerRadius(4)
            }

            // Cards list
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(inventory.proposedCards.enumerated()), id: \.offset) { _, card in
                    cardEntryRow(card)
                }
            }
        }
        .padding(8)
        .background(Color.teal.opacity(0.05))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func cardEntryRow(_ card: DocumentInventory.ProposedCardEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title row with type icon and evidence strength
            HStack(spacing: 6) {
                Image(systemName: cardTypeIcon(card.cardType))
                    .foregroundStyle(cardTypeColor(card.cardType))
                    .font(.caption)

                Text(card.proposedTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)

                Spacer()

                // Evidence strength badge
                Text(card.evidenceStrength.rawValue.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(evidenceStrengthColor(card.evidenceStrength).opacity(0.15))
                    .foregroundStyle(evidenceStrengthColor(card.evidenceStrength))
                    .cornerRadius(3)
            }

            // Key facts (if any)
            if !card.keyFactStatements.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(card.keyFactStatements.prefix(3), id: \.self) { fact in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(fact)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    if card.keyFactStatements.count > 3 {
                        Text("+\(card.keyFactStatements.count - 3) more facts")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Technologies as badges
            if !card.technologies.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(card.technologies.prefix(8), id: \.self) { tech in
                        badgePill(tech, color: .indigo)
                    }
                    if card.technologies.count > 8 {
                        Text("+\(card.technologies.count - 8)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Date range if available
            if let dateRange = card.dateRange, !dateRange.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(dateRange)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(4)
    }

    private func cardTypeIcon(_ type: DocumentInventory.ProposedCardEntry.CardType) -> String {
        switch type {
        case .employment: return "briefcase.fill"
        case .project: return "hammer.fill"
        case .skill: return "lightbulb.fill"
        case .achievement: return "star.fill"
        case .education: return "graduationcap.fill"
        }
    }

    private func cardTypeColor(_ type: DocumentInventory.ProposedCardEntry.CardType) -> Color {
        switch type {
        case .employment: return .blue
        case .project: return .orange
        case .skill: return .purple
        case .achievement: return .yellow
        case .education: return .green
        }
    }

    private func evidenceStrengthColor(_ strength: DocumentInventory.ProposedCardEntry.EvidenceStrength) -> Color {
        switch strength {
        case .primary: return .green
        case .supporting: return .blue
        case .mention: return .gray
        }
    }

    @ViewBuilder
    private func gitAnalysisSection(analysis: JSON) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Repository summary
            if let repoSummary = analysis["repository_summary"].dictionary {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                        Text(analysis["repository_summary"]["name"].stringValue)
                            .font(.caption.weight(.semibold))
                    }
                    Text(analysis["repository_summary"]["description"].stringValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if let domain = repoSummary["primary_domain"]?.stringValue, !domain.isEmpty {
                            badgePill(domain, color: .blue)
                        }
                        if let projectType = repoSummary["project_type"]?.stringValue, !projectType.isEmpty {
                            badgePill(projectType, color: .purple)
                        }
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(6)
            }

            // Technical skills
            if let skills = analysis["technical_skills"].array, !skills.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Technical Skills (\(skills.count))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 4) {
                        ForEach(skills.prefix(20).indices, id: \.self) { index in
                            let skill = skills[index]
                            let proficiency = skill["proficiency_level"].stringValue
                            let color = proficiencyColor(proficiency)
                            badgePill(skill["skill_name"].stringValue, color: color)
                        }
                    }
                }
            }

            // Notable achievements
            if let achievements = analysis["notable_achievements"].array, !achievements.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notable Achievements (\(achievements.count))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(achievements.prefix(5).indices, id: \.self) { index in
                            let achievement = achievements[index]
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                Text(achievement["resume_bullet"].stringValue)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }

            // AI collaboration profile
            if analysis["ai_collaboration_profile"]["detected_ai_usage"].exists() {
                let aiProfile = analysis["ai_collaboration_profile"]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "brain")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                        Text("AI Collaboration")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        let detected = aiProfile["detected_ai_usage"].boolValue
                        badgePill(detected ? "AI Usage Detected" : "No AI Detected",
                                  color: detected ? .purple : .gray)
                        if let rating = aiProfile["collaboration_quality_rating"].string {
                            badgePill(rating.replacingOccurrences(of: "_", with: " ").capitalized,
                                      color: .orange)
                        }
                    }
                }
            }

            // Keyword cloud
            if let keywords = analysis["keyword_cloud"]["primary"].array, !keywords.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keywords")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 4) {
                        ForEach(keywords.prefix(15).indices, id: \.self) { index in
                            badgePill(keywords[index].stringValue, color: .teal)
                        }
                    }
                }
            }
        }
    }

    private func proficiencyColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "expert": return .green
        case "proficient": return .blue
        case "competent": return .orange
        case "familiar": return .gray
        default: return .secondary
        }
    }

    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(4)
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

    @ViewBuilder
    private var fileIcon: some View {
        let icon = iconForContentType(artifact.contentType)
        Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(.secondary)
    }

    private func iconForContentType(_ contentType: String?) -> String {
        guard let contentType else { return "doc" }
        if contentType.contains("pdf") { return "doc.richtext" }
        if contentType.contains("word") || contentType.contains("docx") { return "doc.text" }
        if contentType.contains("image") { return "photo" }
        if contentType.contains("json") { return "curlybraces" }
        if contentType.contains("text") { return "doc.plaintext" }
        if contentType.contains("git") { return "chevron.left.forwardslash.chevron.right" }
        return "doc"
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Flow Layout (for tag pills)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, containerWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, containerWidth: bounds.width).offsets

        for (subview, offset) in zip(subviews, offsets) {
            subview.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(sizes: [CGSize], containerWidth: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX)
        }

        return (offsets, CGSize(width: maxWidth, height: currentY + lineHeight))
    }
}
