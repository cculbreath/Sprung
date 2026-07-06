//
//  DailyTasksModuleView.swift
//  Sprung
//
//  Daily Tasks module wrapper. Also hosts the Discovery onboarding interview:
//  it replaces the daily view until preferences exist, and can be re-run any
//  time via Discovery → Start Discovery Interview (.discoveryStartOnboarding).
//

import SwiftUI

/// Daily Tasks module - wraps existing DailyView
struct DailyTasksModuleView: View {
    @Environment(DiscoveryCoordinator.self) private var coordinator
    @Environment(CandidateDossierStore.self) private var candidateDossierStore
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore
    @State private var triggerTaskGeneration: Bool = false
    @State private var showOnboarding: Bool = false

    var body: some View {
        Group {
            if showOnboarding || coordinator.needsOnboarding {
                DiscoveryOnboardingView(
                    coordinator: coordinator,
                    candidateDossierStore: candidateDossierStore,
                    applicantProfileStore: applicantProfileStore
                ) {
                    showOnboarding = false
                }
            } else {
                DailyView(
                    coordinator: coordinator,
                    triggerTaskGeneration: $triggerTaskGeneration
                )
            }
        }
        .onAppear {
            showOnboarding = coordinator.needsOnboarding
        }
        .onReceive(NotificationCenter.default.publisher(for: .discoveryStartOnboarding)) { _ in
            showOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .discoveryTriggerTaskGeneration)) { _ in
            triggerTaskGeneration = true
        }
    }
}
