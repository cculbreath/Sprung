// import SwiftUI
//
// struct ContentView: View {
//  var modelContext: ModelContext
//  @State private var jobAppStore: JobAppStore = JobAppStore()
//  @State private var resRefStore: ResRefStore = ResRefStore()
//  @State private var resStore: ResStore = ResStore()
//  @State private var coverRefStore: CoverRefStore = CoverRefStore()
//  @State private var coverLetterStore: CoverLetterStore = CoverLetterStore()
//  @State private var showNewAppSheet: Bool = false
//  @State private var cL : CoverLetter? = nil
//  @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
//
//  @State private var selectedJobApp: JobApp? // Track the selected job application
//
//  var body: some View {
//    NavigationSplitView {
//      List(selection: $selectedJobApp) { // Bind selection to `selectedJobApp`
//        ForEach(Statuses.allCases, id: \.self) { status in
//          let filteredApps = jobAppStore.jobApps.filter { $0.status == status }
//          if !filteredApps.isEmpty {
//            Section(header: Text(status.rawValue)) {
//              ForEach(filteredApps, id: \.self) { selApp in
//                Text(selApp.job_position)
//                  .tag(selApp) // Tag each item for the selection
//                  .contextMenu {
//                    Button(role: .destructive) {
//                      jobAppStore.deleteJobApp(selApp)
//                    } label: {
//                      Label("Delete", systemImage: "trash")
//                    }
//                  }
//              }
//            }
//          }
//        }
//      }
//      .listStyle(.sidebar)
//      .navigationTitle("Job Applications")
//      .safeAreaInset(edge: .bottom) {
//        Button(action: { showNewAppSheet = true }) {
//          Label("Add Application", systemImage: "plus.circle.fill")
//        }
//        .controlSize(.regular)
//        .labelStyle(.titleAndIcon)
//        .padding(.bottom, 10)
//        .background(Color.clear)
//        .frame(maxWidth: .infinity, alignment: .leading)
//        .padding(.leading, 10)
//      }
//    } detail: {
//      VStack(alignment: .leading) {
//        if let selApp = selectedJobApp { // Use the selected job application
//          TabWrapperView()
//            .navigationTitle(selApp.job_position)
//        } else {
//          Text("No Selection")
//            .navigationTitle("Job Details")
//        }
//      }
//      .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
//      .background(
//        VStack {
//          Divider()
//          Spacer()
//        }
//      )
//    }
//    .sheet(isPresented: $showNewAppSheet) {
//      NewAppSheetView(
//        scrapingDogApiKey: scrapingDogApiKey,
//        isPresented: $showNewAppSheet
//      )
//    }
//    .onAppear {
//      resRefStore.initialize(context: modelContext)
//      resStore.initialize(context: modelContext)
//      jobAppStore.initialize(context: modelContext, resStore: resStore)
//      coverRefStore.initialize(context: modelContext)
//      coverLetterStore.initialize(context: modelContext, refStore: coverRefStore)
//    }
//    .environment(jobAppStore).environment(resRefStore).environment(resStore).environment(coverRefStore).environment(coverLetterStore)
//  }
// }
