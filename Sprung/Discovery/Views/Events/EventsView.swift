//
//  EventsView.swift
//  Sprung
//
//  Networking events view for discovering and managing events.
//  Displays events grouped by status with preparation and debrief tracking.
//

import SwiftUI

enum EventsViewMode: String, CaseIterable {
    case list = "List"
    case calendar = "Calendar"

    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .calendar: return "calendar"
        }
    }
}

/// Buckets an event date relative to a 7-day "this week" window.
/// Pure and testable: no `Date()` inside — `now` is always injected.
enum EventWeekBucket {
    case thisWeek
    case comingUp

    /// Day-granularity comparison via the injected calendar. Today counts as
    /// `.thisWeek`; a day-difference of 7 or more is `.comingUp`.
    static func bucket(for date: Date, now: Date, calendar: Calendar) -> EventWeekBucket {
        let startOfNow = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let dayDifference = calendar.dateComponents([.day], from: startOfNow, to: startOfDate).day ?? 0
        return dayDifference < 7 ? .thisWeek : .comingUp
    }
}

struct EventsView: View {
    let coordinator: DiscoveryCoordinator
    @Binding var triggerEventDiscovery: Bool
    @Binding var viewMode: EventsViewMode
    @State private var selectedEventType: NetworkingEventType?

    init(coordinator: DiscoveryCoordinator, triggerEventDiscovery: Binding<Bool> = .constant(false), viewMode: Binding<EventsViewMode> = .constant(.list)) {
        self.coordinator = coordinator
        self._triggerEventDiscovery = triggerEventDiscovery
        self._viewMode = viewMode
    }

    // MARK: - Filtered Collections

    private var filteredUpcoming: [NetworkingEventOpportunity] {
        applyFilter(coordinator.eventStore.upcomingEvents)
    }

    private var thisWeekUpcoming: [NetworkingEventOpportunity] {
        filteredUpcoming.filter {
            EventWeekBucket.bucket(for: $0.date, now: Date(), calendar: .current) == .thisWeek
        }
    }

    private var comingUpUpcoming: [NetworkingEventOpportunity] {
        filteredUpcoming.filter {
            EventWeekBucket.bucket(for: $0.date, now: Date(), calendar: .current) == .comingUp
        }
    }

    private var filteredDiscovered: [NetworkingEventOpportunity] {
        applyFilter(coordinator.eventStore.discoveredEvents)
    }

    private var filteredNeedsDebrief: [NetworkingEventOpportunity] {
        applyFilter(coordinator.eventStore.needsDebrief)
    }

    private func applyFilter(_ events: [NetworkingEventOpportunity]) -> [NetworkingEventOpportunity] {
        guard let eventType = selectedEventType else { return events }
        return events.filter { $0.eventType == eventType }
    }

    private var availableEventTypes: [NetworkingEventType] {
        let used = Set(coordinator.eventStore.allEvents.map { $0.eventType })
        return NetworkingEventType.allCases.filter { used.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.eventsDiscovery.isActive {
                discoveryProgressView
            } else if coordinator.eventStore.allEvents.isEmpty {
                emptyStateView
            } else {
                switch viewMode {
                case .list:
                    eventListView
                case .calendar:
                    EventCalendarView(coordinator: coordinator)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("")
        .onChange(of: triggerEventDiscovery) { _, newValue in
            if newValue {
                triggerEventDiscovery = false
                coordinator.startEventDiscovery()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Networking Events")
                .font(.title)

            Text("Discover and prepare for networking events.\nTrack attendance and debrief after each event.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            DiscoverEventsButton(coordinator: coordinator, prominent: true)
        }
    }

    private var discoveryProgressView: some View {
        VStack(spacing: 16) {
            AnimatedThinkingText(
                statusMessage: coordinator.eventsDiscovery.status.message.isEmpty ? "Discovering events..." : coordinator.eventsDiscovery.status.message
            )

            if !coordinator.eventsDiscovery.reasoningText.isEmpty {
                ScrollView {
                    Text(coordinator.eventsDiscovery.reasoningText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 300)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            Button("Cancel") {
                coordinator.cancelEventDiscovery()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var eventListView: some View {
        VStack(spacing: 0) {
            // Discover trigger (with optional one-run guidance)
            HStack {
                Spacer()
                DiscoverEventsButton(coordinator: coordinator)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Event type filter bar
            if availableEventTypes.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FilterChip(label: "All", isSelected: selectedEventType == nil) {
                            selectedEventType = nil
                        }
                        ForEach(availableEventTypes, id: \.self) { eventType in
                            FilterChip(label: eventType.rawValue, isSelected: selectedEventType == eventType) {
                                selectedEventType = selectedEventType == eventType ? nil : eventType
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
            }

            List {
                if !thisWeekUpcoming.isEmpty {
                    Section("This Week") {
                        upcomingRows(for: thisWeekUpcoming)
                    }
                }

                if !comingUpUpcoming.isEmpty {
                    Section("Coming Up") {
                        upcomingRows(for: comingUpUpcoming)
                    }
                }

                if !filteredDiscovered.isEmpty {
                    Section("Discovered") {
                        ForEach(filteredDiscovered) { event in
                            NavigationLink {
                                EventPrepView(event: event, coordinator: coordinator)
                            } label: {
                                EventRowView(event: event, store: coordinator.eventStore)
                            }
                            .contextMenu {
                                eventContextMenu(for: event)
                            }
                        }
                    }
                }

                if !filteredNeedsDebrief.isEmpty {
                    Section("Needs Debrief") {
                        ForEach(filteredNeedsDebrief) { event in
                            NavigationLink {
                                DebriefView(event: event, coordinator: coordinator)
                            } label: {
                                EventRowView(event: event, store: coordinator.eventStore)
                            }
                            .contextMenu {
                                eventContextMenu(for: event)
                            }
                        }
                    }
                }
            }
            .scrollEdgeEffect()
        }
    }

    @ViewBuilder
    private func upcomingRows(for events: [NetworkingEventOpportunity]) -> some View {
        ForEach(events) { event in
            NavigationLink {
                EventPrepView(event: event, coordinator: coordinator)
            } label: {
                EventRowView(event: event, store: coordinator.eventStore)
            }
            .contextMenu {
                eventContextMenu(for: event)
            }
        }
    }

    @ViewBuilder
    private func eventContextMenu(for event: NetworkingEventOpportunity) -> some View {
        // Status transitions
        if event.status == .discovered {
            Button {
                coordinator.eventStore.markAsPlanned(event)
            } label: {
                Label("Plan Attendance", systemImage: "calendar.badge.plus")
            }

            Button {
                coordinator.eventStore.markAsSkipped(event)
            } label: {
                Label("Skip Event", systemImage: "forward.end")
            }
        }

        if event.status == .planned {
            Button {
                coordinator.eventStore.markAsAttended(event)
            } label: {
                Label("Mark as Attended", systemImage: "checkmark.circle")
            }
        }

        Divider()

        // Feedback
        Menu("Discovery Feedback") {
            Button {
                coordinator.eventStore.setDiscoveryFeedback(event, feedback: "more")
            } label: {
                Label("More Like This", systemImage: "hand.thumbsup")
            }

            Button {
                coordinator.eventStore.setDiscoveryFeedback(event, feedback: "less")
            } label: {
                Label("Less Like This", systemImage: "hand.thumbsdown")
            }
        }

        Divider()

        Button {
            if let url = URL(string: event.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Open Event Page", systemImage: "safari")
        }
        .disabled(URL(string: event.url) == nil)

        Divider()

        Button(role: .destructive) {
            coordinator.eventStore.delete(event)
        } label: {
            Label("Delete Event", systemImage: "trash")
        }
    }
}

/// Discover-events trigger with an optional one-run guidance popover.
/// Leaving the field empty runs plain discovery; guidance steers the agent's
/// searches and selection but never waives page verification.
private struct DiscoverEventsButton: View {
    let coordinator: DiscoveryCoordinator
    var prominent = false

    @State private var showPopover = false
    @State private var guidanceText = ""

    var body: some View {
        Group {
            if prominent {
                Button("Discover Events") {
                    showPopover = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    showPopover = true
                } label: {
                    Label("Discover", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Discover Networking Events")
                    .font(.headline)

                TextField("Optional guidance for this run", text: $guidanceText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                Text("e.g. \"virtual events only\" or \"focus on the optics conference season\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Discover") {
                        showPopover = false
                        let guidance = guidanceText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guidanceText = ""
                        coordinator.startEventDiscovery(guidance: guidance)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 340)
        }
    }
}

struct EventRowView: View {
    let event: NetworkingEventOpportunity
    let store: NetworkingEventStore
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: event.eventType.icon)
                .foregroundStyle(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.name)
                        .font(.headline)
                        .lineLimit(1)

                    if let feedback = event.discoveryFeedback {
                        Image(systemName: feedback == "more" ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                            .font(.caption2)
                            .foregroundStyle(feedback == "more" ? .green : .orange)
                    }
                }
                HStack(spacing: 6) {
                    Text(event.date, style: .date)
                    if let time = event.time {
                        Text("·")
                        Text(time)
                    }
                    Text("·")
                    Text(event.location)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Status transition button
            statusButton(for: event)

            Text(event.status.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor(for: event.status).opacity(0.15))
                .foregroundStyle(statusColor(for: event.status))
                .cornerRadius(4)

            Button {
                store.delete(event)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
            .help("Delete event")
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private func statusButton(for event: NetworkingEventOpportunity) -> some View {
        switch event.status {
        case .discovered:
            Button("Plan") {
                store.markAsPlanned(event)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .planned:
            Button("Attended") {
                store.markAsAttended(event)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        default:
            EmptyView()
        }
    }

    private func statusColor(for status: EventPipelineStatus) -> Color {
        switch status {
        case .discovered: return .blue
        case .planned: return .orange
        case .attended: return .teal
        case .debriefed: return .gray
        case .skipped: return .secondary
        case .cancelled: return .red
        case .missed: return .red
        }
    }
}
