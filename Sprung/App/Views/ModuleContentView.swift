//
//  ModuleContentView.swift
//  Sprung
//
//  Routes to the appropriate view based on the selected module.
//

import SwiftUI

/// Routes to the appropriate view based on the selected module
struct ModuleContentView: View {
    let module: AppModule

    var body: some View {
        Group {
            switch module {
            case .pipeline:
                PipelineModuleView()

            case .resumeEditor:
                ResumeEditorModuleView()

            case .dailyTasks:
                DailyTasksModuleView()

            case .events:
                EventsModuleView()

            case .contacts:
                ContactsModuleView()

            case .weeklyReview:
                WeeklyReviewModuleView()

            case .references:
                ReferencesModuleView()

            case .experience:
                ExperienceModuleView()

            case .profile:
                ProfileModuleView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(module) // Force view recreation on module change
        // Global background-AI-activity indicator: visible in every module
        // whenever any tracked operation is running, hidden otherwise.
        // Placed outside .id(module) so it survives module switches.
        .overlay(alignment: .bottomTrailing) {
            BackgroundActivityIndicator()
                .padding(12)
        }
    }
}
