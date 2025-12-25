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
        case .pipeline:
            PipelineView(coordinator: coordinator)
        case .sources:
            SourcesView(coordinator: coordinator)
        case .events:
            EventsView(coordinator: coordinator)
        case .contacts:
            ContactsView(coordinator: coordinator)
        }
    }
}

