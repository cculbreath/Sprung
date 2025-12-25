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
    case pipeline = "Pipeline"
    case sources = "Sources"
    case events = "Events"
    case contacts = "Contacts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .daily: return "checklist"
        case .pipeline: return "rectangle.split.3x1"
        case .sources: return "link.circle"
        case .events: return "calendar"
        case .contacts: return "person.2"
        }
    }

    var description: String {
        switch self {
        case .daily: return "Today's tasks and time tracking"
        case .pipeline: return "Application stages kanban"
        case .sources: return "Job boards and career sites"
        case .events: return "Networking events pipeline"
        case .contacts: return "Professional contacts CRM"
        }
    }
}

struct SearchOpsMainView: View {
    @Environment(SearchOpsCoordinator.self) private var coordinator
    @Environment(CoverRefStore.self) private var coverRefStore
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore
    @State private var selectedSection: SearchOpsSection = .daily
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showOnboarding: Bool = false
    @State private var triggerSourceDiscovery: Bool = false
    @State private var triggerEventDiscovery: Bool = false
    @State private var triggerTaskGeneration: Bool = false

    var body: some View {
        Group {
            if showOnboarding || coordinator.needsOnboarding {
                SearchOpsOnboardingView(
                    coordinator: coordinator,
                    coverRefStore: coverRefStore,
                    applicantProfileStore: applicantProfileStore
                ) {
                    showOnboarding = false
                }
            } else {
                mainContent
            }
        }
        .onAppear {
            showOnboarding = coordinator.needsOnboarding
        }
        .onReceive(NotificationCenter.default.publisher(for: .discoveryStartOnboarding)) { _ in
            showOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .discoveryNavigateToSection)) { notification in
            if let section = notification.userInfo?["section"] as? SearchOpsSection {
                selectedSection = section
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .discoveryTriggerSourceDiscovery)) { _ in
            selectedSection = .sources
            triggerSourceDiscovery = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .discoveryTriggerEventDiscovery)) { _ in
            selectedSection = .events
            triggerEventDiscovery = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .discoveryTriggerTaskGeneration)) { _ in
            selectedSection = .daily
            triggerTaskGeneration = true
        }
    }

    private var mainContent: some View {
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
            .navigationTitle("Discovery")
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
            DailyView(coordinator: coordinator, triggerTaskGeneration: $triggerTaskGeneration)
        case .pipeline:
            PipelineView(coordinator: coordinator)
        case .sources:
            SourcesView(coordinator: coordinator, triggerDiscovery: $triggerSourceDiscovery)
        case .events:
            EventsView(coordinator: coordinator, triggerEventDiscovery: $triggerEventDiscovery)
        case .contacts:
            ContactsView(coordinator: coordinator)
        }
    }
}

