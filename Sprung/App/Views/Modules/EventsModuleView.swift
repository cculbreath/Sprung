//
//  EventsModuleView.swift
//  Sprung
//
//  Networking Events module wrapper. View-mode switching and the discover
//  trigger (with its guidance popover) live inside EventsView itself.
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
            )

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
