import Foundation
import SwiftUI

struct TabWrapperView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Environment(ResStore.self) private var resStore: ResStore
  @Environment(ResRefStore.self) private var resRefStore: ResRefStore  // Added resRefStore


  @State private var listingButtons: SaveButtons = SaveButtons(
    edit: false, save: false, cancel: false)
  @State private var selectedTab: TabList = TabList.listing
  @State private var refPopup: Bool = false
  @State private var coverLetterButtons: CoverLetterButtons = CoverLetterButtons(showInspector: false)

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
        CoverLetterView(buttons: $coverLetterButtons)
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
        listingButtons: $listingButtons,
        letterButtons: $coverLetterButtons
      )
    }.onAppear {
      if selResBinding.wrappedValue == nil, let selectedApp = jobAppStore.selectedApp {
        if resRefStore.areRefsOk {
          selResBinding.wrappedValue = resStore.create(
            jobApp: selectedApp,
            sources: resRefStore.defaultSources
          )
        }
        else { refPopup = true}
      }
    }.sheet(isPresented: $refPopup){
      ResRefView(
        refPopup: $refPopup,
        isSourceExpanded: true,
        selRes: selResBinding,
        tab: $selectedTab
      )
      .padding()
    }
  }
}
struct DummyView: View {
  var myText: String
  var body: some View {
    Text(myText)
      .font(.title)
  }
}



struct SaveButtons {
  var edit: Bool = false
  var save: Bool = false
  var cancel: Bool = false
}

struct CoverLetterButtons {
  var showInspector: Bool = false
}
