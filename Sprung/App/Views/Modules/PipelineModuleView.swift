//
//  PipelineModuleView.swift
//  Sprung
//
//  Pipeline/Kanban module wrapper.
//

import SwiftUI

/// Pipeline/Kanban module - wraps existing PipelineView directly
/// Clicking a card navigates to Resume Editor for that job
struct PipelineModuleView: View {
    @Environment(DiscoveryCoordinator.self) private var coordinator
    @Environment(ModuleNavigationService.self) private var navigation
    @Environment(JobAppStore.self) private var jobAppStore
    @Environment(WindowCoordinator.self) private var windowCoordinator

    var body: some View {
        // Full-width Kanban board - no sidebar needed
        PipelineView(coordinator: coordinator)
            .onReceive(NotificationCenter.default.publisher(for: .selectJobApp)) { notification in
                // When a job card is clicked in the Kanban, navigate to Resume Editor
                if let jobAppId = notification.userInfo?["jobAppId"] as? UUID,
                   let job = jobAppStore.jobApps.first(where: { $0.id == jobAppId }) {
                    // Update focus state
                    windowCoordinator.focusState.focusedJob = job
                    jobAppStore.selectedApp = job
                    // Navigate to Resume Editor module
                    navigation.selectModule(.resumeEditor)
                }
            }
    }
}
