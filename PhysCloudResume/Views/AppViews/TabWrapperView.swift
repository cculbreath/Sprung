import Foundation
import SwiftUI

struct TabWrapperView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @State private var listingButtons: SaveButtons = SaveButtons(
    edit: false, save: false, cancel: false)
  @State private var selectedTab: TabList = TabList.listing
  //    @State var llm: LLM

  var body: some View {
    let selResBinding = Binding(
      get: { jobAppStore.selectedApp?.selectedRes },
      set: { jobAppStore.selectedApp?.selectedRes = $0 }
    )

    VStack {
      TabView(selection: $selectedTab) {
        JobAppDetailView(tab: $selectedTab, buttons: $listingButtons)
          .tabItem {
            Label(TabList.listing.rawValue, systemImage: "newspaper")
          }
          .tag(TabList.listing)

        ResumeViewSetup(currentTab: selectedTab, selRes: selResBinding)
          .tabItem {
            Label(
              TabList.resume.rawValue,  // Ensure this matches the enum case
              systemImage: "person.crop.rectangle.stack"
            )
          }
          .tag(TabList.resume)

        Text("Compose Cover Letter Content")
          .tabItem {
            Label(
              TabList.coverLetter.rawValue,
              systemImage: "person.2.crop.square.stack"
            )
          }
          .tag(TabList.coverLetter)

        Text("Submit Application Content")
          .tabItem {
            Label(TabList.submitApp.rawValue, systemImage: "paperplane")
          }
          .tag(TabList.submitApp)
      }
      .padding(.all)
    }
    .toolbar {
      buildToolbar(
        selectedTab: $selectedTab,
        selRes: selResBinding,
        listingButtons: $listingButtons
      )
    }  //.environment(llm)
  }
}

struct DummyView: View {
  var myText: String
  var body: some View {
    Text(myText)
      .font(.title)
  }
}

enum TabList: String {
  case listing = "Job Listing"
  case resume = "Customize Résumé"
  case coverLetter = "Compose Cover Letter"
  case submitApp = "Submit Application"
  case none = "None"
}

struct SaveButtons {
  var edit: Bool = false
  var save: Bool = false
  var cancel: Bool = false
}
