//
//  EventsModuleView.swift
//  Sprung
//
//  Networking Events module wrapper. The Discover action (with its guidance
//  popover) lives in the L1 header here; view-mode switching and the
//  event-type filter bar live inside EventsView itself.
//

import SwiftUI

/// Networking Events module - wraps existing EventsView
struct EventsModuleView: View {
    @Environment(DiscoveryCoordinator.self) private var coordinator
    @State private var triggerEventDiscovery: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Module header
            ModuleHeader(
                title: "Networking Events",
                subtitle: "Discover events, prepare for them, and debrief afterward"
            ) {
                DiscoverEventsButton(coordinator: coordinator)
            }

            // Existing EventsView (NavigationStack for detail push)
            NavigationStack {
                EventsView(
                    coordinator: coordinator,
                    triggerEventDiscovery: $triggerEventDiscovery
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .discoveryTriggerEventDiscovery)) { _ in
            triggerEventDiscovery = true
        }
    }
}
