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
    var body: some View {
        Section(header: RoundedTagView(
            tagText: status.displayName,
            backgroundColor: JobApp.pillColor(status),
            foregroundColor: .white
        )) {
            ForEach(jobApps) { jobApp in
                JobAppRowView(jobApp: jobApp) {
                    deleteAction(jobApp)
                }
            }
        }
    }
}
