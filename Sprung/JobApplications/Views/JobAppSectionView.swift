//
//  JobAppSectionView.swift
//  Sprung
//
//
// JobAppSectionView.swift
import SwiftUI
struct JobAppSectionView: View {
    var status: Statuses
    var jobApps: [JobApp]
    var deleteAction: (JobApp) -> Void
    var rerunPreprocessingAction: ((JobApp) -> Void)?

    var body: some View {
        Section {
            // The status chip is a plain non-selectable row, NOT a section
            // header: macOS List headers float (pin) at the top of the scroll
            // view, and live width changes (pane divider drag, icon-bar
            // toggle) put the topmost header exactly on the pin threshold,
            // flipping it between pinned and inline every frame.
            RoundedTagView(
                tagText: status.displayName,
                backgroundColor: JobApp.pillColor(status),
                foregroundColor: .white
            )
            .selectionDisabled()

            ForEach(jobApps) { jobApp in
                JobAppRowView(
                    jobApp: jobApp,
                    deleteAction: { deleteAction(jobApp) },
                    rerunPreprocessingAction: { rerunPreprocessingAction?(jobApp) }
                )
            }
        }
    }
}
