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
            HStack(spacing: 1) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

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
                if hasActiveAgents {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }
                badgeView(for: tab)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
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
                .font(.caption2.weight(.semibold).monospacedDigit())
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
            // No outer ScrollView - interview components manage their own scrolling
            interviewContent()
                .padding(.horizontal, 4)
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

// MARK: - Artifacts Tab

private struct ArtifactsTabContent: View {
    let coordinator: OnboardingInterviewCoordinator
    @State private var expandedArtifactIds: Set<String> = []
    @State private var artifactToDelete: ArtifactRecord?
    @State private var artifactToDemote: ArtifactRecord?
    @State private var archivedArtifactToDelete: ArtifactRecord?
    @State private var isArchivedSectionExpanded: Bool = false

    private var artifacts: [ArtifactRecord] {
        coordinator.ui.artifactRecords.map { ArtifactRecord(json: $0) }
    }

    private var archivedArtifacts: [ArtifactRecord] {
        coordinator.getArchivedArtifacts().map { ArtifactRecord(json: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current Interview Artifacts
            currentArtifactsSection

            // Previously Imported Section (only show if there are archived artifacts)
            if !archivedArtifacts.isEmpty {
                archivedArtifactsSection
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
        .alert("Permanently Delete Archived Artifact?", isPresented: .init(
            get: { archivedArtifactToDelete != nil },
            set: { if !$0 { archivedArtifactToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                archivedArtifactToDelete = nil
            }
            Button("Delete Permanently", role: .destructive) {
                if let artifact = archivedArtifactToDelete {
                    Task {
                        await coordinator.deleteArchivedArtifact(id: artifact.id)
                    }
                    archivedArtifactToDelete = nil
                }
            }
        } message: {
            if let artifact = archivedArtifactToDelete {
                Text("Are you sure you want to permanently delete \"\(artifact.displayName)\"? This cannot be undone.")
            }
        }
        .alert("Remove from Interview?", isPresented: .init(
            get: { artifactToDemote != nil },
            set: { if !$0 { artifactToDemote = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                artifactToDemote = nil
            }
            Button("Remove", role: .destructive) {
                if let artifact = artifactToDemote {
                    Task {
                        await coordinator.demoteArtifact(id: artifact.id)
                    }
                    artifactToDemote = nil
                }
            }
        } message: {
            if let artifact = artifactToDemote {
                Text("Remove \"\(artifact.displayName)\" from this interview? It will be moved to the archive and can be added back later.")
            }
        }
    }

    @ViewBuilder
    private var currentArtifactsSection: some View {
        if artifacts.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Interview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

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
                        onDemote: {
                            artifactToDemote = artifact
                        },
                        onDelete: {
                            artifactToDelete = artifact
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var archivedArtifactsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Collapsible header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isArchivedSectionExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isArchivedSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text("Previously Imported")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("(\(archivedArtifacts.count))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            if isArchivedSectionExpanded {
                ForEach(archivedArtifacts) { artifact in
                    ArchivedArtifactRow(
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
                        onPromote: {
                            Task {
                                await coordinator.promoteArchivedArtifact(id: artifact.id)
                            }
                        },
                        onDelete: {
                            archivedArtifactToDelete = artifact
                        }
                    )
                }
            }
        }
        .padding(.top, 8)
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
