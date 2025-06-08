// PhysCloudResume/App/Views/ContentView.swift

import SwiftData
import SwiftUI

struct ContentView: View {
    // MARK: - Injected dependencies via SwiftUI Environment

    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(\.appState) private var appState
    // DragInfo is inherited from ContentViewLaunch

    // States managed by ContentView
    @State var tabRefresh: Bool = false
    @State var showNewAppSheet: Bool = false
    @State var showSlidingList: Bool = false
    @State var selectedTab: TabList = .listing
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var showImportSheet: Bool = false

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
                // Only show toolbar when sidebar is visible
                if sidebarVisibility != .detailOnly {
                    SidebarToolbarView(
                        showSlidingList: $showSlidingList,
                        showNewAppSheet: $showNewAppSheet
                    )
                }
            }

        } detail: {
            // --- Detail Column ---
            VStack(alignment: .leading) {
                if jobAppStore.selectedApp != nil {
                    // Embed AppWindowView directly
                    AppWindowView(selectedTab: $selectedTab, tabRefresh: $tabRefresh)
//                        .navigationTitle(" ")
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
            // Note: The main application toolbar is attached within AppWindowView
        }
        .sheet(isPresented: $showNewAppSheet) {
            // NewAppSheetView still presented from ContentView
            NewAppSheetView(
                scrapingDogApiKey: scrapingDogApiKey,
                isPresented: $showNewAppSheet
            )
            .environment(jobAppStore)
        }
        .sheet(isPresented: $showImportSheet) {
            ImportJobAppsFromURLsView()
                .environment(jobAppStore)
        }
        .onChange(of: appState.showImportJobAppsSheet) { _, newValue in
            Logger.debug("🟢 ContentView detected appState.showImportJobAppsSheet changed to: \(newValue)")
            if newValue {
                showImportSheet = true
                // Reset the appState flag
                appState.showImportJobAppsSheet = false
            }
        }
        .onChange(of: jobAppStore.selectedApp) { _, newValue in
            // Sync selected app to AppState for template editor
            appState.selectedJobApp = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowImportJobApps"))) { _ in
            Logger.debug("🟢 ContentView received ShowImportJobApps notification")
            showImportSheet = true
        }
        .onAppear {
            Logger.debug("🟡 ContentView appeared - appState address: \(Unmanaged.passUnretained(appState).toOpaque())")
            Logger.debug("🟡 Initial appState.showImportJobAppsSheet: \(appState.showImportJobAppsSheet)")
            // Initial setup or logging can remain here
            if let storeURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("Model.sqlite")
            {
                Logger.debug("Store URL: \(storeURL.path)")
            }
        }
        // Environment objects (like DragInfo) are inherited from ContentViewLaunch
    }
}
