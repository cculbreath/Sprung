import SwiftData
import SwiftUI

struct ContentView: View {
  var modelContext: ModelContext
  @State private var jobAppStore: JobAppStore = JobAppStore()
  @State private var resRefStore: ResRefStore = ResRefStore()
  @State private var resStore: ResStore = ResStore()
  @State private var showNewAppSheet: Bool = false
  @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"

  var body: some View {

    NavigationSplitView {
      List(
        jobAppStore.jobApps,
        id: \.self,
        selection: $jobAppStore.selectedApp
      ) { selApp in
        Text(selApp.job_position)
          .tag(selApp)
          .contextMenu {
            Button(role: .destructive) {
              jobAppStore.deleteJobApp(selApp)
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
      }
      .listStyle(.sidebar)
      .navigationTitle("Job Applications")
      .safeAreaInset(edge: .bottom) {
        Button(action: { showNewAppSheet = true }) {
          Label("Add Application", systemImage: "plus.circle.fill")
        }
        .controlSize(.regular)
        .labelStyle(.titleAndIcon)
        .padding(.bottom, 10)
        .background(Color.clear)
        .buttonStyle(BlackOnHoverButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 10)
      }
    } detail: {
      VStack(alignment: .leading) {
        if let selApp = jobAppStore.selectedApp {
          TabWrapperView()
            .navigationTitle(selApp.job_position)
        } else {
          Text("No Selection")
            .navigationTitle("Job Details")
        }
      }
      .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      .background(
        VStack {
          Divider()
          Spacer()
        }
      )
    }
    .sheet(isPresented: $showNewAppSheet) {
      NewAppSheetView(
        scrapingDogApiKey: scrapingDogApiKey,
        isPresented: $showNewAppSheet
      )
    }
    .onAppear {
      resRefStore.initialize(context: modelContext)
      resStore.initialize(context: modelContext)
      jobAppStore.initialize(context: modelContext, resStore: resStore)

    }
    .environment(jobAppStore).environment(resRefStore).environment(resStore)
  }
}



struct BlackOnHoverButtonStyle: ButtonStyle {
  @State private var isHovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundColor(isHovered ? .black : .primary)
      .onHover { hovering in
        isHovered = hovering
      }
  }
}
