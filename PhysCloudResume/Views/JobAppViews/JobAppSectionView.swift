//
//  JobAppSectionView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/30/25.
//

// JobAppSectionView.swift

import SwiftUI

struct JobAppSectionView: View {
    var status: Statuses
    var jobApps: [JobApp]
    var deleteAction: (JobApp) -> Void

    var body: some View {
        Section(header: RoundedTagView(
            tagText: status.rawValue,
            backgroundColor: JobApp.pillColor(status.rawValue),
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
