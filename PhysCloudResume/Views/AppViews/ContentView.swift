import SwiftData
import SwiftUI

struct ContentView: View {
    // MARK: - Injected dependencies via SwiftUI Environment

    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    @Environment(ResStore.self) private var resStore: ResStore
    @Environment(CoverRefStore.self) private var coverRefStore: CoverRefStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(ResModelStore.self) private var resModelStore: ResModelStore

    // Live query for JobApps displayed in the sidebar list
    @Query(sort: \JobApp.jobPosition) private var jobApps: [JobApp]
    @State var dragInfo: DragInfo = .init()
    @State var tabRefresh: Bool = false
    @State var showNewAppSheet: Bool = false
    @State var showSlidingList: Bool = false
    @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
    @AppStorage("availableStyles") var availableStylesString: String = "Typewriter"

    @State var selectedTab: TabList = .listing

    @Namespace private var slidingAnimation // Animation namespace
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .doubleColumn // Show sidebar by default

    var body: some View {
        @Bindable var jobAppStore = jobAppStore

        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $sidebarVisibility) { // Detect sidebar state
                VStack(spacing: 0) {
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
                    .frame(maxHeight: .infinity)

                    if showSlidingList {
                        DraggableSlidingSourceListView(refresh: $tabRefresh, isVisible: $showSlidingList)
                            .transition(.move(edge: .bottom))
                            .zIndex(1)
                    }
                }.padding(.top, 20)
                    .frame(maxHeight: .infinity)
                    .toolbar {
                        Spacer()
                        if sidebarVisibility != .detailOnly { // Hide toolbar when sidebar is closed
                            Button(action: {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.2)) {
                                    showSlidingList.toggle()
                                }
                            }) {
                                Label(
                                    showSlidingList ? "Hide Additional List" : "Show Additional List",
                                    systemImage: "append.page"
                                )
                                .foregroundColor(showSlidingList ? .accentColor : .primary)
                            }

                            // AI Job Recommendation Button
                            SidebarRecommendButton()

                            // New Application Button
                            Button(action: {
                                showNewAppSheet = true
                            }) {
                                Label("New Application", systemImage: "plus.square.on.square").foregroundColor(.primary)
                            }
                        }
                    }
                    .frame(minWidth: 220, maxWidth: .infinity)
            } detail: {
                DetailView(selectedTab: $selectedTab, tabRefresh: $tabRefresh)
            }.sheet(isPresented: $showNewAppSheet) {
                NewAppSheetView(
                    scrapingDogApiKey: scrapingDogApiKey,
                    isPresented: $showNewAppSheet
                )
            }

            Spacer()
        }
        .onAppear {
            if let storeURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("Model.sqlite")
            {
                print("Database location: \(storeURL.path)")
            }
        }
        .environment(dragInfo)
    }
}
