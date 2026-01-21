//
//  WeeklyReviewModuleView.swift
//  Sprung
//
//  Weekly Review module wrapper.
//

import SwiftUI

/// Weekly Review module - wraps existing WeeklyReviewView
struct WeeklyReviewModuleView: View {
    @Environment(DiscoveryCoordinator.self) private var coordinator

    var body: some View {
        VStack(spacing: 0) {
            // Module header
            ModuleHeader(
                title: "Weekly Review",
                subtitle: "Reflect on progress with AI-powered insights"
            )

            // Existing WeeklyReviewView
            WeeklyReviewView(coordinator: coordinator)
        }
    }
}
