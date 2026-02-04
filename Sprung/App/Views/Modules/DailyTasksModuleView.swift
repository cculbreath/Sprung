//
//  DailyTasksModuleView.swift
//  Sprung
//
//  Daily Tasks module wrapper.
//

import SwiftUI

/// Daily Tasks module - wraps existing DailyView
struct DailyTasksModuleView: View {
    @Environment(DiscoveryCoordinator.self) private var coordinator
    @State private var triggerTaskGeneration: Bool = false

    var body: some View {
        DailyView(
            coordinator: coordinator,
            triggerTaskGeneration: $triggerTaskGeneration
        )
        .onReceive(NotificationCenter.default.publisher(for: .discoveryTriggerTaskGeneration)) { _ in
            triggerTaskGeneration = true
        }
    }
}
