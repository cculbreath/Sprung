import SwiftUI
import SwiftyJSON

/// Tabbed view for the tool pane showing interview content, timeline cards, artifacts, and knowledge cards.
/// The Interview tab shows LLM-surfaced interactive content; other tabs provide browse access to collected data.
struct ToolPaneTabsView<InterviewContent: View>: View {
    enum Tab: String, CaseIterable {
        case interview = "Interview"
        case timeline = "Timeline"
        case artifacts = "Artifacts"
        case knowledge = "Knowledge"
        case agents = "Agents"

        var icon: String {
            switch self {
            case .interview: return "bubble.left.and.bubble.right"
            case .timeline: return "calendar.badge.clock"
            case .artifacts: return "doc.text"
            case .knowledge: return "brain.head.profile"
            case .agents: return "person.2.wave.2"
            }
        }
    }

    let coordinator: OnboardingInterviewCoordinator
    @ViewBuilder let interviewContent: () -> InterviewContent
    @Binding var selectedTab: Tab

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            Divider()
                .padding(.vertical, 8)

            // Tab content
            tabContent
        }
    }

    private func tabButton(for tab: Tab) -> some View {
        let hasActiveAgents = tab == .agents && coordinator.agentActivityTracker.isAnyRunning

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.caption2)
                Text(tab.rawValue)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .fixedSize()
                badgeView(for: tab)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .foregroundStyle(selectedTab == tab ? Color.accentColor : (hasActiveAgents ? Color.orange : .secondary))
            .overlay {
                if hasActiveAgents {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.orange.opacity(0.6), lineWidth: 1.5)
                }
            }
            .shadow(color: hasActiveAgents ? Color.orange.opacity(0.5) : .clear, radius: hasActiveAgents ? 4 : 0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.3), value: hasActiveAgents)
    }

    @ViewBuilder
    private func badgeView(for tab: Tab) -> some View {
        let total = tabItemTotal(for: tab)
        if total != 0 {
            Text("\(total)")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule()
                        .fill(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                )
        }
    }

    private func tabItemTotal(for tab: Tab) -> Int {
        switch tab {
        case .interview:
            return 0 // Interview tab doesn't show a count badge
        case .timeline:
            let experiences = coordinator.ui.skeletonTimeline?["experiences"].array
            return experiences?.isEmpty == false ? experiences!.count : 0
        case .artifacts:
            return coordinator.ui.artifactRecords.isEmpty ? 0 : coordinator.ui.artifactRecords.count
        case .knowledge:
            // Show total knowledge cards count
            return coordinator.allKnowledgeCards.count
        case .agents:
            // Show active agents count
            return coordinator.agentActivityTracker.agents.filter { $0.status == .running }.count
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .interview:
            ScrollView {
                interviewContent()
                    .padding(.horizontal, 4)
            }
        case .timeline:
            ScrollView {
                TimelineTabContent(coordinator: coordinator)
                    .padding(.horizontal, 4)
            }
        case .artifacts:
            ScrollView {
                ArtifactsTabContent(coordinator: coordinator)
                    .padding(.horizontal, 4)
            }
        case .knowledge:
            ScrollView {
                KnowledgeTabContent(coordinator: coordinator)
                    .padding(.horizontal, 4)
            }
        case .agents:
            AgentsTabContent(tracker: coordinator.agentActivityTracker)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - Timeline Tab

private struct TimelineTabContent: View {
    let coordinator: OnboardingInterviewCoordinator

    private var experiences: [JSON] {
        coordinator.ui.skeletonTimeline?["experiences"].array ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if experiences.isEmpty {
                emptyState
            } else {
                ForEach(Array(experiences.enumerated()), id: \.offset) { _, experience in
                    TimelineCardRow(experience: experience)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Timeline Cards",
            systemImage: "calendar.badge.clock",
            description: Text("Timeline cards will appear here as they're created during the interview.")
        )
        .frame(height: 180)
    }
}

private struct TimelineCardRow: View {
    let experience: JSON

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(experience["title"].stringValue)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Text(experience["organization"].stringValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                experienceTypeBadge
            }

            HStack(spacing: 6) {
                if let start = experience["start"].string {
                    Text(formatDate(start))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if experience["start"].string != nil {
                    Text("–")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                let end = experience["end"].string ?? ""
                Text(end.isEmpty ? "Present" : formatDate(end))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var experienceTypeBadge: some View {
        let type = experience["experience_type"].string ?? "work"
        let (color, label) = typeInfo(for: type)

        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .cornerRadius(4)
    }

    private func typeInfo(for type: String) -> (Color, String) {
        switch type {
        case "education": return (.purple, "Education")
        case "volunteer": return (.orange, "Volunteer")
        case "project": return (.green, "Project")
        default: return (.blue, "Work")
        }
    }

    private func formatDate(_ dateString: String) -> String {
        // Handle various ISO formats: YYYY, YYYY-MM, YYYY-MM-DD
        let components = dateString.split(separator: "-")
        guard let year = components.first else { return dateString }

        if components.count >= 2, let month = Int(components[1]) {
            let monthNames = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if month > 0, month < 13 {
                return "\(monthNames[month]) \(year)"
            }
        }

        return String(year)
    }
}

// MARK: - Artifacts Tab

private struct ArtifactsTabContent: View {
    let coordinator: OnboardingInterviewCoordinator
    @State private var expandedArtifactIds: Set<String> = []
    @State private var artifactToDelete: ArtifactRecord?

    private var artifacts: [ArtifactRecord] {
        coordinator.ui.artifactRecords.map { ArtifactRecord(json: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if artifacts.isEmpty {
                emptyState
            } else {
                ForEach(artifacts) { artifact in
                    ArtifactRow(
                        artifact: artifact,
                        isExpanded: expandedArtifactIds.contains(artifact.id),
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedArtifactIds.contains(artifact.id) {
                                    expandedArtifactIds.remove(artifact.id)
                                } else {
                                    expandedArtifactIds.insert(artifact.id)
                                }
                            }
                        },
                        onDelete: {
                            artifactToDelete = artifact
                        }
                    )
                }
            }
        }
        .alert("Delete Artifact?", isPresented: .init(
            get: { artifactToDelete != nil },
            set: { if !$0 { artifactToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                artifactToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let artifact = artifactToDelete {
                    Task {
                        await coordinator.deleteArtifactRecord(id: artifact.id)
                    }
                    artifactToDelete = nil
                }
            }
        } message: {
            if let artifact = artifactToDelete {
                Text("Are you sure you want to delete \"\(artifact.displayName)\"? The LLM will be notified that this artifact is no longer available.")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Artifacts",
            systemImage: "doc.text",
            description: Text("Uploaded documents and files will appear here.")
        )
        .frame(height: 180)
    }
}

private struct ArtifactRow: View {
    let artifact: ArtifactRecord
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onDelete: () -> Void

    private var hasContent: Bool {
        !artifact.extractedContent.isEmpty
    }

    private var contentPreview: String {
        let content = artifact.extractedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.count <= 100 {
            return content
        }
        return String(content.prefix(100)) + "..."
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

                        if hasContent {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
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

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete artifact")
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

                    if hasContent {
                        // Content section
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

                            ScrollView {
                                Text(artifact.extractedContent)
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

// MARK: - Knowledge Cards Tab

private struct KnowledgeTabContent: View {
    let coordinator: OnboardingInterviewCoordinator
    @State private var showBrowser = false

    private var allCards: [ResRef] {
        coordinator.allKnowledgeCards
    }

    private var planItems: [KnowledgeCardPlanItem] {
        coordinator.ui.knowledgeCardPlan
    }

    private var resRefStore: ResRefStore {
        coordinator.getResRefStore()
    }

    var body: some View {
        VStack(spacing: 16) {
            // Summary card
            summaryCard

            // Open browser button
            Button(action: { showBrowser = true }) {
                HStack {
                    Image(systemName: "rectangle.stack")
                    Text("Browse All Cards")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.medium))
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Onboarding progress (if in interview)
            if !planItems.isEmpty {
                onboardingProgressSection
            }
        }
        .sheet(isPresented: $showBrowser) {
            KnowledgeCardBrowserOverlay(
                isPresented: $showBrowser,
                cards: .init(
                    get: { allCards },
                    set: { _ in }
                ),
                resRefStore: resRefStore,
                onCardUpdated: { card in
                    resRefStore.updateResRef(card)
                },
                onCardDeleted: { card in
                    resRefStore.deleteResRef(card)
                },
                onCardAdded: { card in
                    resRefStore.addResRef(card)
                }
            )
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(.purple)
                Text("Knowledge Cards")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            HStack(spacing: 16) {
                statItem(count: allCards.count, label: "Total")
                statItem(
                    count: allCards.filter { $0.cardType?.lowercased() == "job" }.count,
                    label: "Jobs",
                    color: .blue
                )
                statItem(
                    count: allCards.filter { $0.cardType?.lowercased() == "skill" }.count,
                    label: "Skills",
                    color: .purple
                )
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func statItem(count: Int, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var onboardingProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Onboarding Progress")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                let completed = planItems.filter { $0.status == .completed }.count
                Text("\(completed)/\(planItems.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            // Progress bar
            GeometryReader { geometry in
                let completed = planItems.filter { $0.status == .completed }.count
                let progress = planItems.isEmpty ? 0 : CGFloat(completed) / CGFloat(planItems.count)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green)
                        .frame(width: geometry.size.width * progress, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

