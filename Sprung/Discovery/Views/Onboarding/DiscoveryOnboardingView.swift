//
//  DiscoveryOnboardingView.swift
//  Sprung
//
//  Onboarding flow for Discovery module. Collects job search preferences
//  needed for LLM-powered task generation and source discovery.
//

import SwiftUI

struct DiscoveryOnboardingView: View {
    let coordinator: DiscoveryCoordinator
    let candidateDossierStore: CandidateDossierStore
    let applicantProfileStore: ApplicantProfileStore
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var selectedSectors: Set<String> = []
    @State private var location: String = ""
    @State private var remoteAcceptable: Bool = true
    @State private var preferredArrangement: WorkArrangement = .hybrid
    @State private var companySizePreference: CompanySizePreference = .any
    @State private var weeklyApplicationTarget: Int = 5
    @State private var weeklyNetworkingTarget: Int = 2
    @State private var isDiscovering: Bool = false
    @State private var discoveryError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressBar

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    switch currentStep {
                    case 0:
                        DiscoveryWelcomeStepView()
                    case 1:
                        DiscoverySectorsStepView(
                            coordinator: coordinator,
                            candidateDossierStore: candidateDossierStore,
                            applicantProfileStore: applicantProfileStore,
                            selectedSectors: $selectedSectors,
                            location: $location,
                            remoteAcceptable: $remoteAcceptable,
                            preferredArrangement: $preferredArrangement,
                            companySizePreference: $companySizePreference
                        )
                    case 2:
                        DiscoveryLocationStepView(
                            location: $location,
                            remoteAcceptable: $remoteAcceptable,
                            preferredArrangement: $preferredArrangement,
                            companySizePreference: $companySizePreference
                        )
                    case 3:
                        DiscoveryGoalsStepView(
                            weeklyApplicationTarget: $weeklyApplicationTarget,
                            weeklyNetworkingTarget: $weeklyNetworkingTarget
                        )
                    case 4:
                        DiscoverySetupStepView(
                            coordinator: coordinator,
                            isDiscovering: isDiscovering,
                            discoveryError: discoveryError,
                            selectedSectors: selectedSectors,
                            location: location,
                            weeklyApplicationTarget: weeklyApplicationTarget,
                            weeklyNetworkingTarget: weeklyNetworkingTarget,
                            onContinueAnyway: completeOnboarding
                        )
                    default:
                        EmptyView()
                    }
                }
                .padding(32)
            }

            Divider()

            // Navigation buttons
            navigationButtons
        }
        .frame(minWidth: 500, minHeight: 500)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))

                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * progressFraction)
                    .animation(.easeInOut, value: currentStep)
            }
        }
        .frame(height: 4)
    }

    private var progressFraction: CGFloat {
        CGFloat(currentStep + 1) / 5.0
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation {
                        currentStep -= 1
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStep < 4 {
                Button("Continue") {
                    withAnimation {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
            } else {
                Button("Get Started") {
                    Task { await startSetup() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDiscovering)
            }
        }
        .padding()
    }

    private var canContinue: Bool {
        switch currentStep {
        case 1:
            return !selectedSectors.isEmpty
        case 2:
            return !location.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return true
        }
    }

    // MARK: - Actions

    private func startSetup() async {
        isDiscovering = true
        discoveryError = nil

        // Save preferences
        var prefs = coordinator.preferencesStore.current()
        prefs.targetSectors = Array(selectedSectors)
        prefs.primaryLocation = location
        prefs.remoteAcceptable = remoteAcceptable
        prefs.preferredArrangement = preferredArrangement
        prefs.companySizePreference = companySizePreference
        prefs.weeklyApplicationTarget = weeklyApplicationTarget
        prefs.weeklyNetworkingTarget = weeklyNetworkingTarget
        coordinator.preferencesStore.update(prefs)

        // Update weekly goal
        let goal = coordinator.weeklyGoalStore.currentWeek()
        goal.applicationTarget = weeklyApplicationTarget
        goal.eventsAttendedTarget = weeklyNetworkingTarget

        // Try to discover sources and generate tasks
        do {
            try await coordinator.discoverJobSources()
            try await coordinator.generateDailyTasks()
            completeOnboarding()
        } catch {
            Logger.error("Onboarding setup failed: \(error)", category: .ai)
            discoveryError = "Could not connect to AI service. You can discover sources manually later."
        }

        isDiscovering = false
    }

    private func completeOnboarding() {
        onComplete()
    }
}
