import SwiftData
import SwiftUI

struct ContentView: View {
    // MARK: - State Variables

    @State private var jobAppStore: JobAppStore = .init()
    @State private var resRefStore: ResRefStore = .init()
    @State private var resStore: ResStore = .init()
    @State private var coverRefStore: CoverRefStore = .init()
    @State private var coverLetterStore: CoverLetterStore = .init()
    @State private var resModelStore: ResModelStore = .init()
    @State var dragInfo: DragInfo = .init()
    @State var tabRefresh: Bool = false
    @State var showNewAppSheet: Bool = false
    @State var showSlidingList: Bool = false
    @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
    @AppStorage("availableStyles") var availableStylesString: String = "Typewriter"

    @State var selectedTab: TabList = .listing
    var modelContext: ModelContext

    @Namespace private var slidingAnimation // Animation namespace
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic // Track sidebar

    var body: some View {
        @Bindable var jobAppStore = jobAppStore

        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $sidebarVisibility) { // Detect sidebar state
                VStack(spacing: 0) {
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
                    .frame(maxHeight: .infinity)

                    if showSlidingList {
                        SlidingSourceListView(refresh: $tabRefresh)
                            .transition(.move(edge: .bottom)) // Use transition to slide in from the bottom
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
            ResModel.defaultStyle = availableStylesString
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first!
            resRefStore.initialize(context: modelContext)
            resStore.initialize(context: modelContext)
            coverLetterStore.initialize(context: modelContext, refStore: coverRefStore)
            jobAppStore.initialize(context: modelContext, resStore: resStore, coverLetterStore: coverLetterStore)
            coverRefStore.initialize(context: modelContext)
            resModelStore.initialize(context: modelContext, resStore: resStore)
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
