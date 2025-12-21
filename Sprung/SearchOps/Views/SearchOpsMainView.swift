//
//  SearchOpsMainView.swift
//  Sprung
//
//  Main window view for Job Search Operations module.
//  Provides sidebar navigation to Daily, Sources, Events, and Contacts views.
//

import SwiftUI

enum SearchOpsSection: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case sources = "Sources"
    case events = "Events"
    case contacts = "Contacts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .daily: return "checklist"
        case .sources: return "link.circle"
        case .events: return "calendar"
        case .contacts: return "person.2"
        }
    }

    var description: String {
        switch self {
        case .daily: return "Today's tasks and time tracking"
        case .sources: return "Job boards and career sites"
        case .events: return "Networking events pipeline"
        case .contacts: return "Professional contacts CRM"
        }
    }
}

struct SearchOpsMainView: View {
    @Environment(SearchOpsCoordinator.self) private var coordinator
    @State private var selectedSection: SearchOpsSection = .daily
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            List(selection: $selectedSection) {
                ForEach(SearchOpsSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.rawValue)
                                    .font(.headline)
                                Text(section.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: section.icon)
                                .foregroundStyle(.blue)
                        }
                    }
                    .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Search Ops")
            .frame(minWidth: 200, idealWidth: 220)
        } detail: {
            // Detail view based on selection
            detailView(for: selectedSection)
                .frame(minWidth: 500)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func detailView(for section: SearchOpsSection) -> some View {
        switch section {
        case .daily:
            DailyView(coordinator: coordinator)
        case .sources:
            SourcesView(coordinator: coordinator)
        case .events:
            EventsView(coordinator: coordinator)
        case .contacts:
            ContactsView(coordinator: coordinator)
        }
    }
}

// MARK: - Placeholder Views (to be implemented)

struct SourcesView: View {
    let coordinator: SearchOpsCoordinator
    @State private var isDiscovering = false

    var body: some View {
        VStack(spacing: 20) {
            if coordinator.jobSourceStore.sources.isEmpty {
                Spacer()

                Image(systemName: "link.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Job Sources")
                    .font(.title)

                Text("Track job boards, company career pages, and other sources.\nMark when you visit them and track which sources yield results.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400)

                Button {
                    Task { await discoverSources() }
                } label: {
                    if isDiscovering {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Discover Sources")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDiscovering)

                Spacer()
            } else {
                List {
                    Section {
                        ForEach(coordinator.jobSourceStore.dueSources) { source in
                            SourceRowView(source: source, coordinator: coordinator)
                        }
                    } header: {
                        if !coordinator.jobSourceStore.dueSources.isEmpty {
                            Text("Due for Visit")
                        }
                    }

                    Section("All Sources") {
                        ForEach(coordinator.jobSourceStore.sources) { source in
                            SourceRowView(source: source, coordinator: coordinator)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await discoverSources() }
                        } label: {
                            if isDiscovering {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "plus")
                            }
                        }
                        .disabled(isDiscovering)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Job Sources")
    }

    private func discoverSources() async {
        isDiscovering = true
        defer { isDiscovering = false }

        do {
            try await coordinator.discoverJobSources()
        } catch {
            Logger.error("Failed to discover sources: \(error)", category: .ai)
        }
    }
}

struct SourceRowView: View {
    let source: JobSource
    let coordinator: SearchOpsCoordinator

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.headline)
                Text(source.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if source.isDue {
                Text("Due")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(4)
            }

            if let days = source.daysSinceVisit {
                Text("\(days)d ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Visit") {
                coordinator.visitSource(source)
                if let url = URL(string: source.url) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

struct EventsView: View {
    let coordinator: SearchOpsCoordinator

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

            if coordinator.eventStore.allEvents.isEmpty {
                Button("Discover Events") {
                    // TODO: Trigger LLM event discovery
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

struct ContactsView: View {
    let coordinator: SearchOpsCoordinator

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Networking Contacts")
                .font(.title)

            Text("Track professional contacts, relationship warmth,\nand follow-up actions.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            if coordinator.contactStore.allContacts.isEmpty {
                Button("Add Contact") {
                    // TODO: Show add contact sheet
                }
                .buttonStyle(.borderedProminent)
            } else {
                List {
                    if !coordinator.contactStore.needsAttention.isEmpty {
                        Section("Needs Attention") {
                            ForEach(coordinator.contactStore.needsAttention) { contact in
                                ContactRowView(contact: contact)
                            }
                        }
                    }

                    if !coordinator.contactStore.hotContacts.isEmpty {
                        Section("Hot Contacts") {
                            ForEach(coordinator.contactStore.hotContacts) { contact in
                                ContactRowView(contact: contact)
                            }
                        }
                    }

                    Section("All Contacts") {
                        ForEach(coordinator.contactStore.allContacts) { contact in
                            ContactRowView(contact: contact)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Contacts")
    }
}

struct ContactRowView: View {
    let contact: NetworkingContact

    var body: some View {
        HStack {
            Image(systemName: contact.relationshipHealth.icon)
                .foregroundStyle(healthColor(contact.relationshipHealth))

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName)
                    .font(.headline)
                if let info = contact.companyAndTitle {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(contact.warmth.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(warmthColor(contact.warmth).opacity(0.2))
                .cornerRadius(4)

            if let days = contact.daysSinceContact {
                Text("\(days)d")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func healthColor(_ health: RelationshipHealth) -> Color {
        switch health {
        case .healthy: return .green
        case .needsAttention: return .orange
        case .decaying: return .red
        case .dormant: return .gray
        case .new: return .blue
        }
    }

    private func warmthColor(_ warmth: ContactWarmth) -> Color {
        switch warmth {
        case .hot: return .red
        case .warm: return .orange
        case .cold: return .blue
        case .dormant: return .gray
        }
    }
}
