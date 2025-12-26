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
    let coordinator: SearchOpsCoordinator
    @Binding var triggerEventDiscovery: Bool
    @State private var isDiscovering = false
    @State private var reasoningText = ""
    @State private var discoveryStatus: DiscoveryStatus = .idle
    @State private var viewMode: EventsViewMode = .list

    init(coordinator: SearchOpsCoordinator, triggerEventDiscovery: Binding<Bool> = .constant(false)) {
        self.coordinator = coordinator
        self._triggerEventDiscovery = triggerEventDiscovery
    }

    var body: some View {
        VStack(spacing: 0) {
            if isDiscovering {
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
                if !isDiscovering && !coordinator.eventStore.allEvents.isEmpty {
                    Button {
                        Task { await discoverEvents() }
                    } label: {
                        Label("Discover More", systemImage: "magnifyingglass")
                    }
                }
            }
        }
        .onChange(of: triggerEventDiscovery) { _, newValue in
            if newValue {
                triggerEventDiscovery = false
                Task { await discoverEvents() }
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
                Task { await discoverEvents() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var discoveryProgressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text(discoveryStatus.message.isEmpty ? "Discovering events..." : discoveryStatus.message)
                .font(.headline)

            if !reasoningText.isEmpty {
                ScrollView {
                    Text(reasoningText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 300)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
            }
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
                    }
                }
            }
        }
    }

    private func discoverEvents() async {
        isDiscovering = true
        reasoningText = ""
        discoveryStatus = .starting
        defer {
            isDiscovering = false
            discoveryStatus = .idle
        }
        do {
            try await coordinator.discoverNetworkingEvents { status, reasoning in
                discoveryStatus = status
                if let reasoning = reasoning {
                    reasoningText += reasoning
                }
            }
        } catch {
            Logger.error("Failed to discover events: \(error)", category: .ai)
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
