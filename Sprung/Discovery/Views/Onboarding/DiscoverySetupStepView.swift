//
//  DiscoverySetupStepView.swift
//  Sprung
//
//  Step 4 of Discovery onboarding: in-progress/error/success display for async setup.
//

import SwiftUI

struct DiscoverySetupStepView: View {
    let coordinator: DiscoveryCoordinator
    let isDiscovering: Bool
    let discoveryError: String?
    let selectedSectors: Set<String>
    let location: String
    let weeklyApplicationTarget: Int
    let weeklyNetworkingTarget: Int
    let onContinueAnyway: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            if isDiscovering {
                AnimatedThinkingText(statusMessage: "Discovering job sources and generating tasks...")

                // Show dynamic status from coordinator
                Text(coordinator.discoveryStatus.message.isEmpty ? "Setting up your job search" : coordinator.discoveryStatus.message)
                    .font(.title3)
                    .padding(.top, 8)
                    .animation(.easeInOut(duration: 0.3), value: coordinator.discoveryStatus.message)
            } else if let error = discoveryError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Setup encountered an issue")
                    .font(.title3)

                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Continue Anyway") {
                    onContinueAnyway()
                }
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("You're all set!")
                    .font(.title)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 12) {
                    OnboardingSummaryRow(label: "Target roles", value: selectedSectors.joined(separator: ", "))
                    OnboardingSummaryRow(label: "Location", value: location)
                    OnboardingSummaryRow(label: "Weekly apps target", value: "\(weeklyApplicationTarget)")
                    OnboardingSummaryRow(label: "Weekly events target", value: "\(weeklyNetworkingTarget)")
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                Text("Click \"Get Started\" to discover job sources and generate your first daily tasks.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
