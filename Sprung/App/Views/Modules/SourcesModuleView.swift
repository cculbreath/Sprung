//
//  SourcesModuleView.swift
//  Sprung
//
//  Job Sources module wrapper.
//

import SwiftUI

/// Job Sources module - wraps existing SourcesView
struct SourcesModuleView: View {
    @Environment(DiscoveryCoordinator.self) private var coordinator
    @State private var triggerDiscovery: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Module header
            ModuleHeader(
                title: "Job Sources",
                subtitle: "Find job boards and company pages tailored to your field"
            )

            // Existing SourcesView
            SourcesView(
                coordinator: coordinator,
                triggerDiscovery: $triggerDiscovery
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .discoveryTriggerSourceDiscovery)) { _ in
            triggerDiscovery = true
        }
    }
}
