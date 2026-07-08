//
//  SidebarView.swift
//  Sprung
//
//
import SwiftData
import SwiftUI
struct SidebarView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    // Live query – sorted by creation time (oldest first) within each status group
    @Query(sort: \JobApp.createdAt, order: .forward) private var jobApps: [JobApp]
    // Binding for the main list selection
    @Binding var selectedApp: JobApp?
    var body: some View {
        VStack(spacing: 0) {
            // --- Main Content ---
            // Main Job Application List - keep JobAppStore in sync with sidebar selection
            List(selection: Binding(
                get: { self.selectedApp },
                set: { newSelection in
                    // Update our binding first
                    self.selectedApp = newSelection
                    // Then ensure JobAppStore is kept in sync - single source of truth
                    jobAppStore.selectedApp = newSelection
                }
            )) {
                ForEach(Statuses.sidebarOrder, id: \.self) { status in
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
                            },
                            rerunPreprocessingAction: { jobApp in
                                jobAppStore.rerunPreprocessing(for: jobApp)
                            }
                        )
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            // Breathing room below the toolbar (replaces the old empty spacer
            // Section, which parked the first section header exactly on the
            // float threshold and made it jitter during live pane resizes).
            .contentMargins(.top, 8, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 20)
            .frame(maxHeight: .infinity) // List takes remaining space
        }
        .frame(maxHeight: .infinity)
    }
}
