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
        // Auto-switch to Timeline tab when LLM activates editor
        .onChange(of: coordinator.ui.isTimelineEditorActive) { _, isActive in
            if isActive && selectedTab != .timeline {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .timeline
                }
            }
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
            // TimelineTabContent manages its own scrolling with sticky footer
            TimelineTabContent(
                coordinator: coordinator,
                mode: coordinator.ui.isTimelineEditorActive ? .editor : .browse,
                onDoneWithTimeline: {
                    Task {
                        await coordinator.completeTimelineEditingAndRequestValidation()
                    }
                }
            )
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
