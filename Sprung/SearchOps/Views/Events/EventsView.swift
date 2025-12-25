//
//  EventsView.swift
//  Sprung
//
//  Networking events view for discovering and managing events.
//  Displays events grouped by status with preparation and debrief tracking.
//

import SwiftUI

struct EventsView: View {
    let coordinator: SearchOpsCoordinator
    @Binding var triggerEventDiscovery: Bool
    @State private var isDiscovering = false

    init(coordinator: SearchOpsCoordinator, triggerEventDiscovery: Binding<Bool> = .constant(false)) {
        self.coordinator = coordinator
        self._triggerEventDiscovery = triggerEventDiscovery
    }

    var body: some View {
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

            if isDiscovering {
                ProgressView("Discovering events...")
            } else if coordinator.eventStore.allEvents.isEmpty {
                Button("Discover Events") {
                    Task { await discoverEvents() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                List {
                    if !coordinator.eventStore.upcomingEvents.isEmpty {
                        Section("Upcoming") {
                            ForEach(coordinator.eventStore.upcomingEvents) { event in
                                EventRowView(event: event)
                            }
                        }
                    }

                    if !coordinator.eventStore.needsDebrief.isEmpty {
                        Section("Needs Debrief") {
                            ForEach(coordinator.eventStore.needsDebrief) { event in
                                EventRowView(event: event)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Events")
        .onChange(of: triggerEventDiscovery) { _, newValue in
            if newValue {
                triggerEventDiscovery = false
                Task { await discoverEvents() }
            }
        }
    }

    private func discoverEvents() async {
        isDiscovering = true
        defer { isDiscovering = false }
        do {
            try await coordinator.discoverNetworkingEvents()
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
