//
//  DailyView.swift
//  Sprung
//
//  Main view for daily job search operations.
//  Shows today's tasks, time spent, and upcoming events.
//

import SwiftUI

struct DailyView: View {
    let coordinator: SearchOpsCoordinator
    @Binding var triggerTaskGeneration: Bool

    @State private var isRefreshing = false

    init(coordinator: SearchOpsCoordinator, triggerTaskGeneration: Binding<Bool> = .constant(false)) {
        self.coordinator = coordinator
        self._triggerTaskGeneration = triggerTaskGeneration
    }

    private var summary: SearchOpsCoordinator.DailySummary {
        coordinator.todaysSummary()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with date and time
                headerSection

                // Time spent today
                timeSection

                // Events needing debrief
                if !coordinator.eventStore.needsDebrief.isEmpty {
                    debriefSection
                }

                // Today's networking events
                if !summary.eventsToday.isEmpty {
                    todaysEventsSection
                }

                // Networking tasks (high priority)
                if hasNetworkingTasks {
                    networkingTasksSection
                }

                // Follow-up tasks
                if hasFollowUpTasks {
                    followUpTasksSection
                }

                // Application tasks
                if hasApplicationTasks {
                    applicationTasksSection
                }

                // Gather tasks
                if hasGatherTasks {
                    gatherTasksSection
                }

                // Contacts needing attention
                if !summary.contactsNeedingAttention.isEmpty {
                    contactsSection
                }

                // Weekly progress
                weeklyProgressSection
            }
            .padding()
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refreshTasks() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .onChange(of: triggerTaskGeneration) { _, newValue in
            if newValue {
                triggerTaskGeneration = false
                Task { await refreshTasks() }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(Date(), style: .date)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Time: \(coordinator.timeEntryStore.formattedTotalForDate(Date()))")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Weekly progress summary
            VStack(alignment: .trailing) {
                let goal = coordinator.weeklyGoalStore.currentWeek()
                Text("This week: \(goal.applicationActual)/\(goal.applicationTarget) apps")
                    .font(.subheadline)
                if goal.eventsAttendedTarget > 0 {
                    Text("\(goal.eventsAttendedActual)/\(goal.eventsAttendedTarget) events")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Time Section

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Time Spent")
                    .font(.headline)
                Spacer()
                Text(coordinator.timeEntryStore.formattedTotalForDate(Date()))
                    .font(.headline)
                    .foregroundStyle(.blue)
            }

            // Activity breakdown
            let breakdown = coordinator.timeEntryStore.todaysBreakdown
            if !breakdown.isEmpty {
                ForEach(breakdown.sorted(by: { $0.value > $1.value }), id: \.key) { activity, minutes in
                    HStack {
                        Image(systemName: activityIcon(activity))
                            .foregroundStyle(activityColor(activity))
                        Text(activity.rawValue)
                            .font(.subheadline)
                        Spacer()
                        Text("\(minutes)m")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private func activityIcon(_ activity: ActivityType) -> String {
        switch activity {
        case .gathering: return "magnifyingglass"
        case .customizing: return "pencil"
        case .applying: return "paperplane"
        case .researching: return "book"
        case .interviewPrep: return "person.2"
        case .networking: return "person.3"
        case .llmChat: return "bubble.left.and.bubble.right"
        case .appActive: return "app"
        case .other: return "ellipsis"
        }
    }

    private func activityColor(_ activity: ActivityType) -> Color {
        switch activity {
        case .customizing: return .blue
        case .gathering: return .green
        case .applying: return .purple
        case .networking: return .orange
        case .interviewPrep: return .red
        default: return .gray
        }
    }

    // MARK: - Debrief Section

    private var debriefSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("NEEDS DEBRIEF", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(coordinator.eventStore.needsDebrief) { event in
                EventDebriefCard(event: event)
            }
        }
    }

    // MARK: - Today's Events

    private var todaysEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("TODAY'S EVENTS", systemImage: "calendar")
                .font(.headline)

            ForEach(summary.eventsToday) { event in
                UpcomingEventCard(event: event)
            }
        }
    }

    // MARK: - Task Sections

    private var hasNetworkingTasks: Bool {
        !coordinator.dailyTaskStore.tasks(ofType: .networking).isEmpty ||
        !coordinator.dailyTaskStore.tasks(ofType: .eventPrep).isEmpty ||
        !coordinator.dailyTaskStore.tasks(ofType: .eventDebrief).isEmpty
    }

    private var networkingTasksSection: some View {
        TaskSection(
            title: "NETWORKING",
            icon: "person.2",
            iconColor: .orange,
            tasks: coordinator.dailyTaskStore.tasks(ofType: .networking) +
                   coordinator.dailyTaskStore.tasks(ofType: .eventPrep) +
                   coordinator.dailyTaskStore.tasks(ofType: .eventDebrief),
            onComplete: { task in
                coordinator.dailyTaskStore.complete(task)
            }
        )
    }

    private var hasFollowUpTasks: Bool {
        !coordinator.dailyTaskStore.tasks(ofType: .followUp).isEmpty
    }

    private var followUpTasksSection: some View {
        TaskSection(
            title: "FOLLOW UP",
            icon: "arrow.uturn.right",
            iconColor: .purple,
            tasks: coordinator.dailyTaskStore.tasks(ofType: .followUp),
            onComplete: { task in
                coordinator.dailyTaskStore.complete(task)
            }
        )
    }

    private var hasApplicationTasks: Bool {
        !coordinator.dailyTaskStore.tasks(ofType: .submitApplication).isEmpty ||
        !coordinator.dailyTaskStore.tasks(ofType: .customizeMaterials).isEmpty
    }

    private var applicationTasksSection: some View {
        TaskSection(
            title: "APPLY",
            icon: "paperplane",
            iconColor: .blue,
            tasks: coordinator.dailyTaskStore.tasks(ofType: .submitApplication) +
                   coordinator.dailyTaskStore.tasks(ofType: .customizeMaterials),
            onComplete: { task in
                coordinator.dailyTaskStore.complete(task)
                if task.taskType == .submitApplication {
                    coordinator.weeklyGoalStore.incrementApplications()
                }
            }
        )
    }

    private var hasGatherTasks: Bool {
        !coordinator.dailyTaskStore.tasks(ofType: .gatherLeads).isEmpty
    }

    private var gatherTasksSection: some View {
        TaskSection(
            title: "GATHER",
            icon: "magnifyingglass",
            iconColor: .green,
            tasks: coordinator.dailyTaskStore.tasks(ofType: .gatherLeads),
            onComplete: { task in
                coordinator.dailyTaskStore.complete(task)
                if let sourceId = task.relatedJobSourceId,
                   let source = coordinator.jobSourceStore.source(byId: sourceId) {
                    coordinator.jobSourceStore.markVisited(source)
                }
            }
        )
    }

    // MARK: - Contacts Section

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("CONTACTS NEEDING ATTENTION", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(.yellow)

            ForEach(summary.contactsNeedingAttention) { contact in
                ContactAttentionCard(contact: contact)
            }
        }
    }

    // MARK: - Weekly Progress

    private var weeklyProgressSection: some View {
        let goal = coordinator.weeklyGoalStore.currentWeek()

        return VStack(alignment: .leading, spacing: 12) {
            Text("WEEKLY PROGRESS")
                .font(.headline)

            HStack(spacing: 20) {
                ProgressIndicator(
                    label: "Applications",
                    current: goal.applicationActual,
                    target: goal.applicationTarget,
                    color: .blue
                )

                ProgressIndicator(
                    label: "Events",
                    current: goal.eventsAttendedActual,
                    target: goal.eventsAttendedTarget,
                    color: .orange
                )

                ProgressIndicator(
                    label: "Contacts",
                    current: goal.newContactsActual,
                    target: goal.newContactsTarget,
                    color: .green
                )

                ProgressIndicator(
                    label: "Follow-ups",
                    current: goal.followUpsSentActual,
                    target: goal.followUpsSentTarget,
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func refreshTasks() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await coordinator.generateDailyTasks()
        } catch {
            Logger.error("Failed to generate daily tasks: \(error)", category: .ai)
        }
    }
}

// MARK: - Supporting Views

struct TaskSection: View {
    let title: String
    let icon: String
    let iconColor: Color
    let tasks: [DailyTask]
    let onComplete: (DailyTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(iconColor)

            ForEach(tasks) { task in
                DailyTaskRow(task: task, onComplete: { onComplete(task) })
            }
        }
    }
}

struct DailyTaskRow: View {
    let task: DailyTask
    let onComplete: () -> Void

    var body: some View {
        HStack {
            Button(action: onComplete) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                if let description = task.taskDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let minutes = task.estimatedMinutes {
                Text("~\(minutes)m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EventDebriefCard: View {
    let event: NetworkingEventOpportunity

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(event.name)
                    .fontWeight(.medium)
                Text("You attended · Capture your contacts!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Debrief →") {
                // TODO: Navigate to debrief view
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

struct UpcomingEventCard: View {
    let event: NetworkingEventOpportunity

    var body: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundStyle(.blue)

            VStack(alignment: .leading) {
                Text(event.name)
                    .fontWeight(.medium)
                if let time = event.time {
                    Text(time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if event.status == .planned {
                Button("View Prep") {
                    // TODO: Navigate to prep view
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ContactAttentionCard: View {
    let contact: NetworkingContact

    var body: some View {
        HStack {
            Image(systemName: contact.relationshipHealth.icon)
                .foregroundStyle(healthColor(contact.relationshipHealth))

            VStack(alignment: .leading) {
                Text(contact.displayName)
                    .fontWeight(.medium)
                if let company = contact.company {
                    Text(company)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let days = contact.daysSinceContact {
                    Text("Last contact: \(days) days ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Log Action") {
                // TODO: Navigate to interaction logging
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private func healthColor(_ health: RelationshipHealth) -> Color {
        switch health {
        case .healthy: return .green
        case .needsAttention: return .yellow
        case .decaying: return .orange
        case .dormant: return .gray
        case .new: return .blue
        }
    }
}

struct ProgressIndicator: View {
    let label: String
    let current: Int
    let target: Int
    let color: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, Double(current) / Double(target))
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(current)/\(target)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .frame(width: 44, height: 44)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
