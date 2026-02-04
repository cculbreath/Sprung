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

            case .sources:
                SourcesModuleView()

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
        .toolbar(id: "sprungMainToolbar") {
            if !module.hasCustomToolbar {
                // Same customizable toolbar ID as Resume Editor ensures macOS
                // preserves toolbar configuration across module switches.
                // A hidden Label forces iconAndLabel height allocation.
                ToolbarItem(id: "moduleReserve", placement: .navigation, showsByDefault: true) {
                    Label("Sprung", systemImage: "diamond")
                        .hidden()
                }
            }
        }
    }
}
