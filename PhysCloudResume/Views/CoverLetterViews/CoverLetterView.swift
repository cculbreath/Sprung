import SwiftUI

struct CoverLetterView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Environment(CoverRefStore.self) private var coverRefStore: CoverRefStore
  @Environment(CoverLetterStore.self) private var coverLetterStore:
    CoverLetterStore

  @Binding var buttons: CoverLetterButtons
  @State private var selectedInspectorTab: InspectorTab = .references  // State to manage selected tab

  var body: some View {
    contentView()
  }

  @ViewBuilder
  private func contentView() -> some View {
    @Bindable var coverLetterStore = coverLetterStore
    @Bindable var jobAppStore = jobAppStore

    if let jobApp = $jobAppStore.wrappedValue.selectedApp,
      let res = jobApp.selectedRes
    {

      let resBinding = Binding(
        get: { res },
        set: { jobApp.selectedRes = $0 }
      )

      VStack {
        CoverLetterContentView(
          res: resBinding,
          jobApp: jobApp,
          buttons: $buttons
        )
      }
      .inspector(isPresented: $buttons.showInspector) {
        if $coverLetterStore.wrappedValue.cL != nil {
          VStack(alignment: .leading) {
            // Segmented Picker without a label for switching between "References" and "Revisions"
            Picker("", selection: $selectedInspectorTab) {
              Text("References").tag(InspectorTab.references)
              Text("Revisions").tag(InspectorTab.revisions)
            }
            .pickerStyle(SegmentedPickerStyle())  // Segmented control style

            // Conditionally display content based on the selected tab
            switch selectedInspectorTab {
            case .references:
              CoverRefView(
                backgroundFacts: coverRefStore.backgroundRefs,
                writingSamples: coverRefStore.writingSamples
              )
            case .revisions:
              CoverRevisionsView(
                buttons: $buttons
              )  // Placeholder for your yet-to-be-written Revisions panel
            }
          }
          .frame(maxHeight: .infinity, alignment: .top)  // Ensure the content aligns at the top
          .padding()  // Optional padding
        } else {
          EmptyView()
        }
      }
    } else {
      Text(
        jobAppStore.selectedApp?.selectedRes == nil
          ? "job app nil" : "No nil fail"
      )
      .onAppear {
        if jobAppStore.selectedApp == nil {
          print("no job app")
        } else if jobAppStore.selectedApp?.selectedRes == nil {
          print("no resume")
        }
      }
    }
  }
}

// Enum to manage the tab selection
enum InspectorTab {
  case references
  case revisions
}

// Placeholder for the Revisions view (to be written)

struct CoverLetterContentView: View {
  @Environment(CoverRefStore.self) private var coverRefStore: CoverRefStore
  @Environment(CoverLetterStore.self) private var coverLetterStore:
    CoverLetterStore
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

  @Binding var res: Resume
  @Bindable var jobApp: JobApp
  @Binding var buttons: CoverLetterButtons
  @State var loading: Bool = false

  var body: some View {
    @Bindable var coverLetterStore = coverLetterStore
    @Bindable var bindStore = jobAppStore
    if let app = jobAppStore.selectedApp,
      let cL = jobAppStore.selectedApp?.selectedCover
    {
      @Bindable var bindApp = app
      VStack {
        HStack {
          Picker(
            "Load existing cover letter",
            selection: Binding(
              get: { jobAppStore.selectedApp?.selectedCover },
              set: { newCoverLetter in
                loading = true
                jobAppStore.selectedApp?.selectedCover = newCoverLetter
 }
            )
          ) {
            ForEach(
              app.coverLetters.sorted(by: { $0.moddedDate < $1.moddedDate }),
              id: \.id
            ) { letter in
              Text("Generated at \(letter.modDate)")
                .tag(letter as CoverLetter?)
            }
          }.padding()
          if loading {
            ProgressView()
          } else {
            EmptyView()
          }
        }
        Text("AI generated text at \(cL.modDate)")
          .font(.caption)
          .italic()

        // ScrollView that occupies all available vertical space
        ScrollView {
          Text(cL.content)
            .font(.body)
            .padding()
        }
        .frame(maxHeight: .infinity)  // Make the ScrollView fill the available vertical space
        .id(cL.id)  // Force SwiftUI to recognize content change
      }
      .onChange(of: jobAppStore.selectedApp?.selectedCover) {
        oldval, newCover in
        print("Cover letter changed to: \(newCover?.modDate ?? "None")")
        loading = false
      }
    } else {
      EmptyView()
    }
  }
}
