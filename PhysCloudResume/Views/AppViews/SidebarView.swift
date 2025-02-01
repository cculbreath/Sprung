// SidebarView.swift

import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Binding var showNewAppSheet: Bool
    @Binding var showSlidingList: Bool

    var body: some View {
        @Bindable var jobAppStore = jobAppStore
        List(selection: $jobAppStore.selectedApp) {
            ForEach(Statuses.allCases, id: \.self) { status in
                let filteredApps: [JobApp] = jobAppStore.jobApps.filter { $0.status == status }
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
        // No toolbar here
    }
}
