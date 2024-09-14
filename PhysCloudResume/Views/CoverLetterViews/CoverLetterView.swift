import SwiftUI

struct CoverLetterView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Environment(CoverRefStore.self) private var coverRefStore: CoverRefStore
  @Environment(CoverLetterStore.self) private var  coverLetterStore: CoverLetterStore

  @Binding var buttons: CoverLetterButtons

  var body: some View {
    contentView()
  }

  @ViewBuilder
  private func contentView() -> some View {
    @Bindable var coverLetterStore = coverLetterStore
    @Bindable var jobAppStore = jobAppStore

    if let jobApp = $jobAppStore.wrappedValue.selectedApp,
       let res = jobApp.selectedRes {

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
          CoverRefView(
            backgroundFacts: coverRefStore.backgroundRefs,
            writingSamples: coverRefStore.writingSamples
          )
        }
        else {EmptyView()}
      }
    } else {

      Text(
        jobAppStore.selectedApp?.selectedRes == nil  ? "job app nil" : "No nil fail"
      )
      .onAppear{if jobAppStore.selectedApp == nil {print("no job app")}
        else if jobAppStore.selectedApp?.selectedRes == nil {print("no resume")}}
    }
  }
}

struct CoverLetterContentView: View {
  @Environment(CoverRefStore.self) private var coverRefStore: CoverRefStore
  @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore

  @Binding var res: Resume
  @Bindable var jobApp: JobApp
  @Binding var buttons: CoverLetterButtons

  var body: some View {
    @Bindable var coverLetterStore = coverLetterStore
    if $coverLetterStore.wrappedValue.cL != nil {
      VStack {
        Picker(
          "Load existing cover letter",
          selection: $coverLetterStore.cL
        ) {
          ForEach(jobApp.coverLetters, id: \.id) { letter in
            Text("Generated at \(letter.modDate)")
              .tag(letter as CoverLetter)
          }
        }
        Text("AI generated text at \(coverLetterStore.cL!.modDate)")
          .font(.caption).italic()
        Text(coverLetterStore.cL!.content)
          .font(.body)
      }
      .onChange(of: coverLetterStore.cL!.content) { oldValue, newValue in
        print("Cover letter content: \(newValue)")
      }
    }}
}
