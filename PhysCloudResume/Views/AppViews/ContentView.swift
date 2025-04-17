import SwiftData
import SwiftUI
struct ContentView: View {
    // MARK: - State Variables

    @State private var jobAppStore: JobAppStore
    @State private var resRefStore: ResRefStore
    @State private var resStore: ResStore
    @State private var coverRefStore: CoverRefStore
    @State private var coverLetterStore: CoverLetterStore
    @State private var resModelStore: ResModelStore

    // Live query for JobApps displayed in the sidebar list
    @Query(sort: \JobApp.job_position) private var jobApps: [JobApp]
    @State var dragInfo: DragInfo = .init()
    @State var tabRefresh: Bool = false
    @State var showNewAppSheet: Bool = false
    @State var showSlidingList: Bool = false
    @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
    @AppStorage("availableStyles") var availableStylesString: String = "Typewriter"

    @State var selectedTab: TabList = .listing
    let modelContext: ModelContext

    // MARK: - Initialiser

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        // Create stores that do not depend on each other first
        let resStore = ResStore(context: modelContext)
        let resRefStore = ResRefStore(context: modelContext)
        let coverRefStore = CoverRefStore(context: modelContext)
        let coverLetterStore = CoverLetterStore(context: modelContext, refStore: coverRefStore)
        let jobAppStore = JobAppStore(context: modelContext, resStore: resStore, coverLetterStore: coverLetterStore)
        let resModelStore = ResModelStore(context: modelContext, resStore: resStore)

        _resStore = State(initialValue: resStore)
        _resRefStore = State(initialValue: resRefStore)
        _coverRefStore = State(initialValue: coverRefStore)
        _coverLetterStore = State(initialValue: coverLetterStore)
        _jobAppStore = State(initialValue: jobAppStore)
        _resModelStore = State(initialValue: resModelStore)
    }

    @Namespace private var slidingAnimation // Animation namespace
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic // Track sidebar

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
            .appendingPathComponent("Model.sqlite") {
            print("Database location: \(storeURL.path)")
          }
            // Default style preference stored in AppStorage; ResModel instances
            // will receive their style explicitly when created.
        }
        .environment(jobAppStore)
        .environment(resRefStore)
        .environment(resModelStore)
        .environment(resStore)
        .environment(coverRefStore)
        .environment(coverLetterStore)
        .environment(dragInfo)
    }
}
