import SwiftUI

struct TabWrapperView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Environment(ResStore.self) private var resStore: ResStore
  @Environment(ResRefStore.self) private var resRefStore: ResRefStore
  @Environment(CoverRefStore.self) private var coverRefStore: CoverRefStore
  @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore

  @State private var listingButtons: SaveButtons = SaveButtons(edit: false, save: false, cancel: false)
  @State private var selectedTab: TabList = TabList.listing
  @State private var refPopup: Bool = false
  @State private var coverLetterButtons: CoverLetterButtons = CoverLetterButtons(showInspector: false, runRequested: false)

  var body: some View {
    @Bindable var jobAppStore = jobAppStore
    if let jobApp = jobAppStore.selectedApp {
      @Bindable var jobApp = jobApp
      
      
      VStack {
        TabView(selection: $selectedTab) {
          JobAppDetailView(tab: $selectedTab, buttons: $listingButtons)
            .tabItem {
              Label(TabList.listing.rawValue, systemImage: "newspaper")
            }
            .tag(TabList.listing)
          
          ResumeViewSetup(currentTab: selectedTab)
            .tabItem {
              Label(TabList.resume.rawValue, systemImage: "person.crop.rectangle.stack")
            }
            .tag(TabList.resume)
          
          if let _ = jobAppStore.selectedApp {
            
            
            CoverLetterView(buttons: $coverLetterButtons)
              .tabItem {
                Label(TabList.coverLetter.rawValue, systemImage: "person.2.crop.square.stack")
              }
              .tag(TabList.coverLetter)
          }
          
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
          listingButtons: $listingButtons,
          letterButtons: $coverLetterButtons
        )
      }
      .onAppear {
        if  let selectedApp = jobAppStore.selectedApp {
          if selectedApp.selectedRes == nil {
            if resRefStore.areRefsOk {
              selectedApp.selectedRes = resStore.create(jobApp: selectedApp, sources: resRefStore.defaultSources)
            } else {
              refPopup = true
            }
          }
        }
        updateMyLetter()
      }
      .onChange(of: jobAppStore.selectedApp) { _, _ in
        updateMyLetter()
      }
      .sheet(isPresented: $refPopup) {
        ResRefView(
          refPopup: $refPopup,
          isSourceExpanded: true,
          tab: $selectedTab
        )
        .padding()
      }
    }
  }

  func updateMyLetter() {
    print("update cover letter")
    if let selectedApp = jobAppStore.selectedApp {
      if let lastLetter = selectedApp.coverLetters.last {
        coverLetterStore.cL = lastLetter
      } else {
        coverLetterStore.cL = coverLetterStore.create(jobApp: selectedApp)
      }
    } else {
      coverLetterStore.cL = nil
    }
  }

}

struct SaveButtons {
  var edit: Bool = false
  var save: Bool = false
  var cancel: Bool = false
}

struct CoverLetterButtons {
  var showInspector: Bool = false
  var runRequested: Bool = false
}
