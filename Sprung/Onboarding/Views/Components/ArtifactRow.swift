import SwiftUI
import SwiftyJSON

/// Row view for displaying an artifact with expand/collapse, demote, and delete actions.
/// Shows artifact content, metadata, and git analysis when expanded.
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
                            if artifact.hasKnowledgeExtraction {
                                // Content extracted AND knowledge extracted
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                    .help("Content extracted, knowledge extracted")
                            } else if artifact.isWritingSample {
                                // Writing samples don't need knowledge extraction - show success
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                    .help("Writing sample extracted")
                            } else {
                                // Content extracted but NO knowledge extraction yet
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                    .help("No skills or narrative cards extracted")
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

                    // Pending skills section (from SkillStore, with delete buttons)
                    if !pendingSkills.isEmpty {
                        pendingSkillsSection
                    }

                    // Extracted skills section (from artifact JSON, read-only)
                    if let skills = artifact.skills, !skills.isEmpty, pendingSkills.isEmpty {
                        skillsSection(skills)
                    }

                    // Narrative cards section (if available)
                    if let narrativeCards = artifact.narrativeCards, !narrativeCards.isEmpty {
                        narrativeCardsSection(narrativeCards)
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
    private var pendingSkillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.orange)
                Text("Pending Skills (\(pendingSkills.count))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Review before approval")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Skills grouped by category
            let grouped = Dictionary(grouping: pendingSkills) { $0.category }
            ForEach(SkillCategoryUtils.sortedCategories(from: pendingSkills), id: \.self) { category in
                if let categorySkills = grouped[category], !categorySkills.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)

                        ForEach(categorySkills, id: \.id) { skill in
                            HStack(spacing: 6) {
                                Text(skill.canonical)
                                    .font(.caption)
                                    .lineLimit(1)

                                Spacer()

                                Text(skill.proficiency.rawValue.capitalized)
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(proficiencyColor(skill.proficiency).opacity(0.15))
                                    .foregroundStyle(proficiencyColor(skill.proficiency))
                                    .cornerRadius(3)

                                if let deleteAction = onDeleteSkill {
                                    Button {
                                        deleteAction(skill)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption2)
                                            .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove this skill")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func skillsSection(_ skills: [Skill]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.purple)
                Text("Skills (\(skills.count))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let regenAction = onRegenSkills {
                    Button {
                        regenAction()
                    } label: {
                        Image(systemName: "arrow.trianglehead.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Regenerate skills for this artifact")
                }
            }

            // Skills grouped by category
            let grouped = Dictionary(grouping: skills) { $0.category }
            ForEach(SkillCategoryUtils.sortedCategories(from: skills), id: \.self) { category in
                if let categorySkills = grouped[category], !categorySkills.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 4) {
                            ForEach(categorySkills.prefix(10), id: \.canonical) { skill in
                                skillBadge(skill)
                            }
                            if categorySkills.count > 10 {
                                Text("+\(categorySkills.count - 10)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func skillBadge(_ skill: Skill) -> some View {
        HStack(spacing: 2) {
            Text(skill.canonical)
                .font(.caption2)
            if let lastUsed = skill.lastUsed {
                Text("(\(lastUsed))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(proficiencyColor(skill.proficiency).opacity(0.15))
        .foregroundStyle(proficiencyColor(skill.proficiency))
        .cornerRadius(4)
    }

    @ViewBuilder
    private func narrativeCardsSection(_ cards: [KnowledgeCard]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.teal)
                Text("Narrative Cards (\(cards.count))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let regenAction = onRegenNarrativeCards {
                    Button {
                        regenAction()
                    } label: {
                        Image(systemName: "arrow.trianglehead.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Regenerate knowledge cards for this artifact")
                }
            }

            // Cards list
            VStack(alignment: .leading, spacing: 6) {
                ForEach(cards, id: \.id) { card in
                    narrativeCardRow(card)
                }
            }
        }
        .padding(8)
        .background(Color.teal.opacity(0.05))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func narrativeCardRow(_ card: KnowledgeCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title row with type
            HStack(spacing: 6) {
                Image(systemName: cardTypeIcon(card.cardType))
                    .foregroundStyle(cardTypeColor(card.cardType))
                    .font(.caption)

                Text(card.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)

                Spacer()

                Text(card.cardType?.rawValue ?? "general")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(cardTypeColor(card.cardType).opacity(0.15))
                    .foregroundStyle(cardTypeColor(card.cardType))
                    .cornerRadius(3)
            }

            // Organization and date range
            if let org = card.organization {
                HStack(spacing: 4) {
                    Image(systemName: "building.2")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(org)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let dateRange = card.dateRange {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(dateRange)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Narrative preview
            if !card.narrative.isEmpty {
                Text(card.narrative.prefix(150) + (card.narrative.count > 150 ? "..." : ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // Domains as badges
            if !card.extractable.domains.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(card.extractable.domains.prefix(6), id: \.self) { domain in
                        badgePill(domain, color: .indigo)
                    }
                    if card.extractable.domains.count > 6 {
                        Text("+\(card.extractable.domains.count - 6)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(4)
    }

    private func cardTypeIcon(_ type: CardType?) -> String {
        switch type {
        case .employment: return "briefcase.fill"
        case .project: return "hammer.fill"
        case .achievement: return "star.fill"
        case .education: return "graduationcap.fill"
        case nil: return "doc.fill"
        }
    }

    private func cardTypeColor(_ type: CardType?) -> Color {
        switch type {
        case .employment: return .blue
        case .project: return .orange
        case .achievement: return .yellow
        case .education: return .green
        case nil: return .gray
        }
    }

    private func proficiencyColor(_ proficiency: Proficiency) -> Color {
        switch proficiency {
        case .expert: return .green
        case .proficient: return .blue
        case .familiar: return .orange
        }
    }

    @ViewBuilder
    private func gitAnalysisSection(analysis: JSON) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Repository summary
            if let repoSummary = analysis["repositorySummary"].dictionary {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                        Text(analysis["repositorySummary"]["name"].stringValue)
                            .font(.caption.weight(.semibold))
                    }
                    Text(analysis["repositorySummary"]["description"].stringValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if let domain = repoSummary["primaryDomain"]?.stringValue, !domain.isEmpty {
                            badgePill(domain, color: .blue)
                        }
                        if let projectType = repoSummary["projectType"]?.stringValue, !projectType.isEmpty {
                            badgePill(projectType, color: .purple)
                        }
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(6)
            }

            // Technical skills
            if let skills = analysis["technicalSkills"].array, !skills.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Technical Skills (\(skills.count))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 4) {
                        ForEach(skills.prefix(20).indices, id: \.self) { index in
                            let skill = skills[index]
                            let proficiency = skill["proficiencyLevel"].stringValue
                            let color = proficiencyColor(proficiency)
                            badgePill(skill["skillName"].stringValue, color: color)
                        }
                    }
                }
            }

            // Notable achievements
            if let achievements = analysis["notableAchievements"].array, !achievements.isEmpty {
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
                                Text(achievement["resumeBullet"].stringValue)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }

            // AI collaboration profile
            if analysis["aiCollaborationProfile"]["detectedAiUsage"].exists() {
                let aiProfile = analysis["aiCollaborationProfile"]
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
                        let detected = aiProfile["detectedAiUsage"].boolValue
                        badgePill(detected ? "AI Usage Detected" : "No AI Detected",
                                  color: detected ? .purple : .gray)
                        if let rating = aiProfile["collaborationQualityRating"].string {
                            badgePill(rating.replacingOccurrences(of: "_", with: " ").capitalized,
                                      color: .orange)
                        }
                    }
                }
            }

            // Keyword cloud
            if let keywords = analysis["keywordCloud"]["primary"].array, !keywords.isEmpty {
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
