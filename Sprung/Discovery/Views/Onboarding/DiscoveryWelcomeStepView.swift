//
//  DiscoveryWelcomeStepView.swift
//  Sprung
//
//  Step 0 of Discovery onboarding: marketing/feature introduction.
//

import SwiftUI

struct DiscoveryWelcomeStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.stack.3d.down.forward.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to Discovery")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your AI-powered job search command center")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "calendar.day.timeline.leading",
                    title: "Daily Task Management",
                    description: "AI-generated tasks prioritized for maximum impact"
                )

                FeatureRow(
                    icon: "signpost.right.and.left",
                    title: "Smart Source Discovery",
                    description: "Find job boards and company pages tailored to your field"
                )

                FeatureRow(
                    icon: "person.line.dotted.person.fill",
                    title: "Networking Events",
                    description: "Discover, evaluate, and prepare for networking opportunities"
                )

                FeatureRow(
                    icon: "teletype.answer",
                    title: "Contact Management",
                    description: "Track relationships and get follow-up reminders"
                )

                FeatureRow(
                    icon: "book.pages",
                    title: "Weekly Reviews",
                    description: "Reflect on progress with AI-powered insights"
                )
            }
            .padding(.top, 16)
        }
    }
}
