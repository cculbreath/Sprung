//
//  DailyView.swift
//  Sprung
//
//  Main view for daily job search operations.
//  Shows today's tasks and upcoming events; task rows open the job, contact,
//  or event they reference.
//

import SwiftUI

struct DailyView: View {
    let coordinator: DiscoveryCoordinator
    @Binding var triggerTaskGeneration: Bool

    @State private var isRefreshing = false
    @State private var regeneratingCategory: TaskCategory?
    @State private var showingFeedbackSheet = false
    @State private var feedbackText = ""
    @State private var taskGenerationError: String?
    @State private var selectedContact: NetworkingContact?
    @State private var selectedEvent: NetworkingEventOpportunity?

    init(coordinator: DiscoveryCoordinator, triggerTaskGeneration: Binding<Bool> = .constant(false)) {
        self.coordinator = coordinator
        self._triggerTaskGeneration = triggerTaskGeneration
    }

    private var summary: DiscoveryCoordinator.DailySummary {
        coordinator.todaysSummary()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Tasks")
                        .font(.headline)
                    Text("AI-generated tasks prioritized for maximum impact")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await refreshTasks() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.windowBackgroundColor))
            .overlay(alignment: .bottom) {
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with date and weekly summary
                    headerSection

                    // Coaching section (always visible)
                    CoachingSectionView(coordinator: coordinator)

                    // What the last task generation changed (retired/dropped
                    // tasks are never silent)
                    if let outcome = coordinator.dailyTaskGenerator?.lastOutcome, outcome.hasNotes {
                        planChangesSection(outcome)
                    }

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
            .scrollEdgeEffect()
        }
        .navigationTitle("")
        .onChange(of: triggerTaskGeneration) { _, newValue in
            if newValue {
                triggerTaskGeneration = false
                Task { await refreshTasks() }
            }
        }
        .onAppear {
            coordinator.autoStartCoachingIfNeeded()
        }
        .sheet(isPresented: $showingFeedbackSheet) {
            if let category = regeneratingCategory {
                TaskFeedbackSheet(
                    category: category,
                    feedbackText: $feedbackText,
                    onSubmit: {
                        showingFeedbackSheet = false
                        Task { await regenerateTasks() }
                    },
                    onCancel: {
                        showingFeedbackSheet = false
                        regeneratingCategory = nil
                        feedbackText = ""
                    }
                )
            }
        }
        .sheet(item: $selectedContact) { contact in
            ContactDetailSheet(contact: contact, store: coordinator.contactStore)
        }
        .sheet(item: $selectedEvent) { event in
            eventSheet(for: event)
        }
        .alert("Task Generation Failed", isPresented: Binding(
            get: { taskGenerationError != nil },
            set: { if !$0 { taskGenerationError = nil } }
        )) {
            Button("OK") { taskGenerationError = nil }
        } message: {
            Text(taskGenerationError ?? "")
        }
    }

    /// Same prep-or-debrief branch the events calendar uses, hosted in a sheet
    /// (DailyView has no NavigationStack to push onto).
    private func eventSheet(for event: NetworkingEventOpportunity) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { selectedEvent = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding([.top, .horizontal])

            if event.needsDebrief {
                DebriefView(event: event, coordinator: coordinator)
            } else {
                EventPrepView(event: event, coordinator: coordinator)
            }
        }
        .frame(width: 640, height: 700)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text(Date(), style: .date)
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            // Weekly progress summary
            VStack(alignment: .trailing) {
                let goal = coordinator.weeklyGoalStore.currentWeek()
                Text("This week: \(coordinator.weeklyGoalStore.applicationsSubmittedThisWeek())/\(goal.applicationTarget) apps")
                    .font(.subheadline)
                if goal.eventsAttendedTarget > 0 {
                    Text("\(goal.eventsAttendedActual)/\(goal.eventsAttendedTarget) events")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Plan Changes (last task generation)

    private func planChangesSection(_ outcome: DailyTaskGenerationOutcome) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("PLAN CHANGES", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    coordinator.dailyTaskGenerator?.lastOutcome = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }

            if !outcome.summary.isEmpty {
                Text(outcome.summary)
                    .font(.subheadline)
            }

            Text("\(outcome.addedCount) new · \(outcome.carriedOverCount) carried over")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !outcome.retirements.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Retired:")
                        .font(.caption)
                        .fontWeight(.medium)
                    ForEach(outcome.retirements.indices, id: \.self) { index in
                        let retirement = outcome.retirements[index]
                        Text("• \(retirement.title) — \(retirement.reason)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !outcome.droppedTasks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggestions that couldn't be added:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                    ForEach(outcome.droppedTasks.indices, id: \.self) { index in
                        let droppedTask = outcome.droppedTasks[index]
                        Text("• \(droppedTask.title) — \(droppedTask.reason)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
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
        !coordinator.dailyTaskStore.tasks(in: .networking).isEmpty
    }

    private var networkingTasksSection: some View {
        TaskSection(
            title: "NETWORKING",
            icon: "person.2",
            iconColor: .orange,
            tasks: coordinator.dailyTaskStore.tasks(in: .networking),
            category: .networking,
            isRegenerating: regeneratingCategory == .networking,
            onComplete: { task in completeTask(task) },
            onRegenerate: { startRegeneration(for: .networking) },
            onOpen: { task in openRelated(task) }
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
            onComplete: { task in completeTask(task) },
            onOpen: { task in openRelated(task) }
        )
    }

    private var hasApplicationTasks: Bool {
        !coordinator.dailyTaskStore.tasks(in: .apply).isEmpty
    }

    private var applicationTasksSection: some View {
        TaskSection(
            title: "APPLY",
            icon: "paperplane",
            iconColor: .blue,
            tasks: coordinator.dailyTaskStore.tasks(in: .apply),
            category: .apply,
            isRegenerating: regeneratingCategory == .apply,
            onComplete: { task in completeTask(task) },
            onRegenerate: { startRegeneration(for: .apply) },
            onOpen: { task in openRelated(task) }
        )
    }

    private var hasGatherTasks: Bool {
        !coordinator.dailyTaskStore.tasks(in: .gather).isEmpty
    }

    private var gatherTasksSection: some View {
        TaskSection(
            title: "GATHER",
            icon: "magnifyingglass",
            iconColor: .green,
            tasks: coordinator.dailyTaskStore.tasks(in: .gather),
            category: .gather,
            isRegenerating: regeneratingCategory == .gather,
            onComplete: { task in completeTask(task) },
            onRegenerate: { startRegeneration(for: .gather) },
            onOpen: { task in openRelated(task) }
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedContact = contact
                    }
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
                    current: coordinator.weeklyGoalStore.applicationsSubmittedThisWeek(),
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
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Actions

    /// Mark a task done. Completing an outreach task IS the interaction —
    /// advance the contact's relationship clock so the attention nag clears,
    /// and a completed Follow Up also clears the contact's nearest pending
    /// follow-up commitment (the row the debrief created).
    private func completeTask(_ task: DailyTask) {
        guard !task.isCompleted else { return }
        coordinator.dailyTaskStore.complete(task)

        if task.taskType == .followUp || task.taskType == .networking,
           let contactId = task.relatedContactId,
           let contact = coordinator.contactStore.contact(byId: contactId) {
            coordinator.contactStore.recordInteraction(contact, type: task.taskType.rawValue)

            if task.taskType == .followUp {
                coordinator.interactionStore.completeNearestPendingFollowUp(forContactId: contactId)
            }
        }
    }

    /// Open the object a task references: job → main-window selection,
    /// contact → detail sheet, event → prep/debrief sheet.
    private func openRelated(_ task: DailyTask) {
        if let jobId = task.relatedJobAppId,
           let job = coordinator.jobAppStore.jobApp(byId: jobId) {
            selectJob(job)
        } else if let contactId = task.relatedContactId,
                  let contact = coordinator.contactStore.contact(byId: contactId) {
            selectedContact = contact
        } else if let eventId = task.relatedEventId,
                  let event = coordinator.eventStore.event(byId: eventId) {
            selectedEvent = event
        }
    }

    /// Same navigation the pipeline board uses: select the job in the store,
    /// notify the main-window observers, and bring the main window forward.
    private func selectJob(_ job: JobApp) {
        coordinator.jobAppStore.selectedApp = job

        NotificationCenter.default.post(
            name: .selectJobApp,
            object: nil,
            userInfo: ["jobAppId": job.id]
        )

        if let mainWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "myApp" || $0.title.isEmpty }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshTasks() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await coordinator.generateDailyTasks()
        } catch {
            Logger.error("Failed to generate daily tasks: \(error)", category: .ai)
            taskGenerationError = "Couldn't refresh daily tasks — \(error.localizedDescription)"
        }
    }

    private func startRegeneration(for category: TaskCategory) {
        regeneratingCategory = category
        feedbackText = ""
        showingFeedbackSheet = true
    }

    private func regenerateTasks() async {
        guard let category = regeneratingCategory else { return }

        do {
            try await coordinator.regenerateDailyTasks(category: category, feedback: feedbackText)
            regeneratingCategory = nil
            feedbackText = ""
        } catch {
            Logger.error("Failed to regenerate \(category.displayName) tasks: \(error)", category: .ai)
            taskGenerationError = "Couldn't regenerate \(category.displayName) tasks — \(error.localizedDescription)"
        }
    }
}

// MARK: - Task Feedback Sheet

struct TaskFeedbackSheet: View {
    let category: TaskCategory
    @Binding var feedbackText: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Regenerate \(category.displayName) Tasks")
                .font(.headline)

            Text("What would you like different about these suggestions?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $feedbackText)
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            if feedbackText.isEmpty {
                Text("e.g., \"Focus on remote-friendly companies\" or \"I want to prioritize networking events\"")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Regenerate") {
                    onSubmit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Supporting Views

struct TaskSection: View {
    let title: String
    let icon: String
    let iconColor: Color
    let tasks: [DailyTask]
    var category: TaskCategory? = nil
    var isRegenerating: Bool = false
    let onComplete: (DailyTask) -> Void
    var onRegenerate: (() -> Void)? = nil
    var onOpen: ((DailyTask) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(iconColor)

                Spacer()

                if let onRegenerate = onRegenerate {
                    Button {
                        onRegenerate()
                    } label: {
                        if isRegenerating {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(isRegenerating)
                    .help("Regenerate \(category?.displayName ?? "") tasks")
                }
            }

            ForEach(tasks) { task in
                DailyTaskRow(
                    task: task,
                    onComplete: { onComplete(task) },
                    onOpen: openAction(for: task)
                )
            }
        }
    }

    private func openAction(for task: DailyTask) -> (() -> Void)? {
        guard let onOpen else { return nil }
        return { onOpen(task) }
    }
}

struct DailyTaskRow: View {
    let task: DailyTask
    let onComplete: () -> Void
    var onOpen: (() -> Void)? = nil

    /// The row is openable when the generator attached a related object id.
    /// (Stale ids no-op in the open handler rather than hiding the affordance.)
    private var hasRelatedObject: Bool {
        task.relatedJobAppId != nil || task.relatedContactId != nil || task.relatedEventId != nil
    }

    private var isOpenable: Bool {
        onOpen != nil && hasRelatedObject
    }

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

            if isOpenable {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if isOpenable {
                onOpen?()
            }
        }
        .help(isOpenable ? "Open the job, contact, or event this task is about" : "")
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
                Text(contact.name)
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
