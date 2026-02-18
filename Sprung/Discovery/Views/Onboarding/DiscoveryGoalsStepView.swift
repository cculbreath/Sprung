//
//  DiscoveryGoalsStepView.swift
//  Sprung
//
//  Step 3 of Discovery onboarding: weekly application and networking goal steppers.
//

import SwiftUI

struct DiscoveryGoalsStepView: View {
    @Binding var weeklyApplicationTarget: Int
    @Binding var weeklyNetworkingTarget: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set your weekly goals")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("These help us generate appropriate daily tasks and track your progress.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                GoalStepper(
                    title: "Applications per week",
                    value: $weeklyApplicationTarget,
                    range: 1...20,
                    icon: "paperplane",
                    color: .blue
                )

                GoalStepper(
                    title: "Networking events per week",
                    value: $weeklyNetworkingTarget,
                    range: 0...10,
                    icon: "person.2",
                    color: .orange
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tip")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Start with achievable goals. You can adjust these anytime in settings. Consistency beats intensity in a job search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}
