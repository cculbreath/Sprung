// SidebarView.swift

import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    // Live query – any insertion / deletion in SwiftData refreshes the list
    @Query(sort: \JobApp.jobPosition) private var jobApps: [JobApp]

    @Binding var showNewAppSheet: Bool
    @Binding var showSlidingList: Bool

    var body: some View {
        @Bindable var jobAppStore = jobAppStore

        List(selection: $jobAppStore.selectedApp) {
            ForEach(Statuses.allCases, id: \.self) { status in
                let filteredApps = jobApps.filter { $0.status == status }
                if !filteredApps.isEmpty {
                    JobAppSectionView(
                        status: status,
                        jobApps: filteredApps,
                        deleteAction: { jobApp in
                            jobAppStore.deleteJobApp(jobApp)
                        }
                    )
                }
            }
        }
        .listStyle(.sidebar)
    }
}
