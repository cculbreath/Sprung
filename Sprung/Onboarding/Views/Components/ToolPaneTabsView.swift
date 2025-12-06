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

        var icon: String {
            switch self {
            case .interview: return "bubble.left.and.bubble.right"
            case .timeline: return "calendar.badge.clock"
            case .artifacts: return "doc.text"
            case .knowledge: return "brain.head.profile"
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
        Button {
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
            .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
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
            return coordinator.ui.knowledgeCardPlan.isEmpty ? 0 : coordinator.ui.knowledgeCardPlan.count
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
                        }
                    )
                }
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

            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 8) {
                    if hasContent {
                        // Content section
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Extracted Content")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(artifact.extractedContent.count) chars")
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
                    } else {
                        // No content yet
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

            VStack(alignment: .leading, spacing: 2) {
                if let purpose = artifact.metadata["purpose"].string {
                    metadataRow(label: "Purpose", value: purpose)
                }
                if let title = artifact.metadata["title"].string {
                    metadataRow(label: "Title", value: title)
                }
                if let sha = artifact.sha256 {
                    metadataRow(label: "SHA256", value: String(sha.prefix(16)) + "...")
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

    private func formatFileSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Knowledge Cards Tab

private struct KnowledgeTabContent: View {
    let coordinator: OnboardingInterviewCoordinator
    @State private var expandedCardIds: Set<String> = []

    private var planItems: [KnowledgeCardPlanItem] {
        coordinator.ui.knowledgeCardPlan
    }

    /// Persisted knowledge cards from ResRefStore (SwiftData)
    private var knowledgeCards: [ResRef] {
        coordinator.onboardingKnowledgeCards
    }

    private var currentFocus: String? {
        coordinator.ui.knowledgeCardPlanFocus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if planItems.isEmpty {
                emptyState
            } else {
                progressHeader
                ForEach(planItems) { item in
                    KnowledgePlanRow(
                        item: item,
                        resRef: knowledgeCards.first { $0.name == item.title },
                        isFocused: item.id == currentFocus,
                        isExpanded: expandedCardIds.contains(item.id),
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedCardIds.contains(item.id) {
                                    expandedCardIds.remove(item.id)
                                } else {
                                    expandedCardIds.insert(item.id)
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Knowledge Cards",
            systemImage: "brain.head.profile",
            description: Text("Knowledge card plan will appear here during Phase 2.")
        )
        .frame(height: 180)
    }

    private var progressHeader: some View {
        let completed = planItems.filter { $0.status == .completed }.count
        let total = planItems.count

        return HStack {
            Text("Progress")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(completed)/\(total) completed")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }
}

private struct KnowledgePlanRow: View {
    let item: KnowledgeCardPlanItem
    let resRef: ResRef?  // Persisted knowledge card from SwiftData
    let isFocused: Bool
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    private var hasContent: Bool {
        item.description != nil || resRef != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            Button(action: onToggleExpand) {
                HStack(spacing: 8) {
                    statusIcon
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(item.status == .completed ? .secondary : .primary)
                            .lineLimit(1)

                        if !isExpanded, let description = item.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    typeBadge

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 10) {
                    // Description section
                    if let description = item.description {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }

                    // Knowledge card content section (for completed cards)
                    if let resRef = resRef {
                        resRefContentSection(resRef)
                    } else if item.status == .pending {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                            Text("Waiting to be processed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else if item.status == .inProgress {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Currently being generated...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else if item.status == .skipped {
                        HStack {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                            Text("This card was skipped")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    // Metadata row
                    if item.timelineEntryId != nil || resRef?.organization != nil || resRef?.timePeriod != nil {
                        metadataSection
                    }
                }
                .padding(10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(backgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: isFocused || isExpanded ? 1.5 : 1)
        )
    }

    @ViewBuilder
    private func resRefContentSection(_ resRef: ResRef) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Knowledge Card Content")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(resRef.content.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ScrollView {
                Text(resRef.content)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)

            // Sources section (parsed from sourcesJSON)
            if let sourcesJSON = resRef.sourcesJSON,
               let data = sourcesJSON.data(using: .utf8),
               let sources = try? JSON(data: data).array,
               !sources.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sources (\(sources.count))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                        HStack(spacing: 6) {
                            let sourceType = source["type"].stringValue
                            Image(systemName: sourceType == "artifact" ? "doc" : "bubble.left")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if let artifactId = source["artifact_id"].string {
                                Text(artifactId)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else if let excerpt = source["chat_excerpt"].string {
                                Text(excerpt)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            } else {
                                Text(sourceType)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            }
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Details")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                if let org = resRef?.organization {
                    metadataRow(label: "Organization", value: org)
                }
                if let period = resRef?.timePeriod {
                    metadataRow(label: "Period", value: period)
                }
                if let location = resRef?.location {
                    metadataRow(label: "Location", value: location)
                }
                if let timelineId = item.timelineEntryId {
                    metadataRow(label: "Timeline", value: timelineId)
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
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .inProgress:
            Image(systemName: "circle.dotted")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse, options: .repeating)
        case .pending:
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var typeBadge: some View {
        Text(item.type == .job ? "Job" : "Skill")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(item.type == .job ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
            .foregroundStyle(item.type == .job ? .blue : .purple)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        if isFocused && item.status == .inProgress {
            return Color.accentColor.opacity(0.05)
        } else if item.status == .completed {
            return Color.green.opacity(0.03)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isExpanded {
            return Color.accentColor.opacity(0.5)
        } else if isFocused && item.status == .inProgress {
            return Color.accentColor
        } else if item.status == .completed {
            return Color.green.opacity(0.3)
        }
        return Color(nsColor: .separatorColor)
    }
}
