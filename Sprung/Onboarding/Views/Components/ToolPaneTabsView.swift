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

    private var artifacts: [ArtifactRecord] {
        coordinator.ui.artifactRecords.map { ArtifactRecord(json: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if artifacts.isEmpty {
                emptyState
            } else {
                ForEach(artifacts) { artifact in
                    ArtifactRow(artifact: artifact)
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

    var body: some View {
        HStack(spacing: 10) {
            fileIcon
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.filename)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let contentType = artifact.contentType {
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

            if !artifact.extractedContent.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
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

    private var planItems: [KnowledgeCardPlanItem] {
        coordinator.ui.knowledgeCardPlan
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
                    KnowledgePlanRow(item: item, isFocused: item.id == currentFocus)
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
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(item.status == .completed ? .secondary : .primary)
                    .lineLimit(1)

                if let description = item.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            typeBadge
        }
        .padding(10)
        .background(backgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
        )
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
        if isFocused && item.status == .inProgress {
            return Color.accentColor
        } else if item.status == .completed {
            return Color.green.opacity(0.3)
        }
        return Color(nsColor: .separatorColor)
    }
}
