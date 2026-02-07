//
//  EventsModuleView.swift
//  Sprung
//
//  Networking Events module wrapper.
//

import SwiftUI

/// Networking Events module - wraps existing EventsView
struct EventsModuleView: View {
    @Environment(DiscoveryCoordinator.self) private var coordinator
    @State private var triggerEventDiscovery: Bool = false
    @State private var viewMode: EventsViewMode = .list

    var body: some View {
        VStack(spacing: 0) {
            // Module header
            ModuleHeader(
                title: "Networking Events",
                subtitle: "Discover, evaluate, and prepare for networking opportunities",
                actions: {
                    AnyView(
                        HStack(spacing: 8) {
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

                            if !coordinator.eventsDiscovery.isActive && !coordinator.eventStore.allEvents.isEmpty {
                                Button {
                                    coordinator.startEventDiscovery()
                                } label: {
                                    Label("Discover", systemImage: "magnifyingglass")
                                }
                            }
                        }
                    )
                }
            )

            // Existing EventsView (NavigationStack for detail push)
            NavigationStack {
                EventsView(
                    coordinator: coordinator,
                    triggerEventDiscovery: $triggerEventDiscovery,
                    viewMode: $viewMode
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .discoveryTriggerEventDiscovery)) { _ in
            triggerEventDiscovery = true
        }
    }
}
