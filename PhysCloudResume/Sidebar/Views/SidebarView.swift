//
//  SidebarView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on .
//

import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    // Live query – any insertion / deletion in SwiftData refreshes the list
    @Query(sort: \JobApp.jobPosition) private var jobApps: [JobApp]
    @Binding var tabRefresh: Bool // Pass down if needed by DraggableSlidingSourceListView

    // Binding for the main list selection
    @Binding var selectedApp: JobApp?

    // State for the sliding list visibility
    @Binding var showSlidingList: Bool

    // State passed from ContentView for the sheet
    @Binding var showNewAppSheet: Bool

    var body: some View {
        VStack(spacing: 0) {
            // --- Main Content ---
            // Main Job Application List
            List(selection: $selectedApp) {
                ForEach(Statuses.allCases, id: \.self) { status in
                    let filteredApps = jobApps.filter { $0.status == status }
                    if !filteredApps.isEmpty {
                        JobAppSectionView(
                            status: status,
                            jobApps: filteredApps,
                            deleteAction: { jobApp in
                                jobAppStore.deleteJobApp(jobApp)
                                if selectedApp == jobApp {
                                    selectedApp = jobApps.first { $0.id != jobApp.id }
                                }
                            }
                        )
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(maxHeight: .infinity) // List takes remaining space

            // Draggable Sliding Source List (conditionally shown)
            if showSlidingList {
                DraggableSlidingSourceListView(refresh: $tabRefresh, isVisible: $showSlidingList)
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .frame(maxHeight: .infinity) // Ensure VStack takes full height
    }
}
