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

struct EventsView: View {
    let coordinator: DiscoveryCoordinator
    @Binding var triggerEventDiscovery: Bool
    @State private var viewMode: EventsViewMode = .list

    init(coordinator: DiscoveryCoordinator, triggerEventDiscovery: Binding<Bool> = .constant(false)) {
        self.coordinator = coordinator
        self._triggerEventDiscovery = triggerEventDiscovery
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
        .navigationTitle("Events")
        .toolbar {
            ToolbarItem(placement: .principal) {
                if !coordinator.eventStore.allEvents.isEmpty {
                    Picker("View Mode", selection: $viewMode) {
                        ForEach(EventsViewMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if !coordinator.eventsDiscovery.isActive && !coordinator.eventStore.allEvents.isEmpty {
                    Button {
                        coordinator.startEventDiscovery()
                    } label: {
                        Label("Discover More", systemImage: "magnifyingglass")
                    }
                }
            }
        }
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

            Text("Discover, evaluate, and prepare for networking events.\nTrack attendance and debrief after each event.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            Button("Discover Events") {
                coordinator.startEventDiscovery()
            }
            .buttonStyle(.borderedProminent)
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
        List {
            if !coordinator.eventStore.upcomingEvents.isEmpty {
                Section("Upcoming") {
                    ForEach(coordinator.eventStore.upcomingEvents) { event in
                        NavigationLink {
                            EventPrepView(event: event, coordinator: coordinator)
                        } label: {
                            EventRowView(event: event)
                        }
                        .contextMenu {
                            eventContextMenu(for: event)
                        }
                    }
                }
            }

            if !coordinator.eventStore.discoveredEvents.isEmpty {
                Section("Discovered") {
                    ForEach(coordinator.eventStore.discoveredEvents) { event in
                        NavigationLink {
                            EventPrepView(event: event, coordinator: coordinator)
                        } label: {
                            EventRowView(event: event)
                        }
                        .contextMenu {
                            eventContextMenu(for: event)
                        }
                    }
                }
            }

            if !coordinator.eventStore.needsDebrief.isEmpty {
                Section("Needs Debrief") {
                    ForEach(coordinator.eventStore.needsDebrief) { event in
                        NavigationLink {
                            DebriefView(event: event, coordinator: coordinator)
                        } label: {
                            EventRowView(event: event)
                        }
                        .contextMenu {
                            eventContextMenu(for: event)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func eventContextMenu(for event: NetworkingEventOpportunity) -> some View {
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

struct EventRowView: View {
    let event: NetworkingEventOpportunity

    var body: some View {
        HStack {
            Image(systemName: event.eventType.icon)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.name)
                    .font(.headline)
                HStack {
                    Text(event.date, style: .date)
                    if let time = event.time {
                        Text("·")
                        Text(time)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(event.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let recommendation = event.llmRecommendation {
                Image(systemName: recommendation.icon)
                    .foregroundStyle(recommendation == .strongYes ? .green : .secondary)
            }

            Text(event.status.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }
}
