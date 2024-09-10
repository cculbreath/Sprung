import SwiftUI

struct ResumeViewSetup: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Environment(ResRefStore.self) private var resRefStore: ResRefStore
  @Environment(ResStore.self) private var resStore: ResStore
  @State private var isWide = false
  @State var currentTab: TabList
  @Binding var selRes: Resume?

  var body: some View {
    VStack {
      if let jobApp = jobAppStore.selectedApp {
        if jobApp.resumes.isEmpty {
          CreateNewResumeView()
        } else {


          ResumeSplitView(selRes: $selRes, isWide: $isWide, tab: $currentTab)
        }
      } else {
        Text("No job application selected.")
      }
    }
  }
}
