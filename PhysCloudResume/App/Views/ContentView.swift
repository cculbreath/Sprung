// PhysCloudResume/App/Views/ContentView.swift

import SwiftData
import SwiftUI

struct ContentView: View {
    // MARK: - Injected dependencies via SwiftUI Environment

    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    // DragInfo is inherited from ContentViewLaunch

    // States managed by ContentView
    @State var tabRefresh: Bool = false
    @State var showNewAppSheet: Bool = false
    @State var showSlidingList: Bool = false
    @State var selectedTab: TabList = .listing
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .doubleColumn

    // App Storage remains here as it's app-level config
    @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
    @AppStorage("availableStyles") var availableStylesString: String = "Typewriter"

    var body: some View {
        // Bindable reference to the store for selection binding
        @Bindable var jobAppStore = jobAppStore

        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            // --- Sidebar Column ---
            SidebarView(
                tabRefresh: $tabRefresh,
                selectedApp: $jobAppStore.selectedApp, // Pass selection binding
                showSlidingList: $showSlidingList, // Pass sliding list state
                showNewAppSheet: $showNewAppSheet // Pass sheet state down
            )
            .frame(minWidth: 220, maxWidth: .infinity) // Keep min width for sidebar
            .toolbar {
                SidebarToolbarView(
                    showSlidingList: $showSlidingList,
                    showNewAppSheet: $showNewAppSheet
                )
            }

        } detail: {
            // --- Detail Column ---
            VStack(alignment: .leading) {
                if let selApp = jobAppStore.selectedApp {
                    // Embed TabWrapperView directly
                    TabWrapperView(selectedTab: $selectedTab, tabRefresh: $tabRefresh)
                        // Apply navigationTitle here based on selected App
                        .navigationTitle("\(selApp.jobPosition) at \(selApp.companyName)")
                } else {
                    // Placeholder when no job application is selected
                    Text("Select a Job Application")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background( // Add a subtle background or divider for visual separation
                VStack {
                    Divider()
                    Spacer()
                }
                .edgesIgnoringSafeArea(.top) // Allow divider to touch the top edge
            )
            // Note: The main application toolbar is attached within TabWrapperView
        }
        .sheet(isPresented: $showNewAppSheet) {
            // NewAppSheetView still presented from ContentView
            NewAppSheetView(
                scrapingDogApiKey: scrapingDogApiKey,
                isPresented: $showNewAppSheet
            )
        }
        .onAppear {
            // Initial setup or logging can remain here
            if let storeURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("Model.sqlite")
            {
                print("Store URL: \(storeURL.path)")
            }
        }
        // Environment objects (like DragInfo) are inherited from ContentViewLaunch
    }
}
