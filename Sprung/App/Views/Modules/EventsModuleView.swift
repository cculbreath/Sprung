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

    var body: some View {
        VStack(spacing: 0) {
            // Module header
            ModuleHeader(
                title: "Networking Events",
                subtitle: "Discover, evaluate, and prepare for networking opportunities"
            )

            // Existing EventsView
            EventsView(
                coordinator: coordinator,
                triggerEventDiscovery: $triggerEventDiscovery
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .discoveryTriggerEventDiscovery)) { _ in
            triggerEventDiscovery = true
        }
    }
}
