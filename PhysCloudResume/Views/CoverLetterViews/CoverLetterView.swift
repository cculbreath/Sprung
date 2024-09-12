//
//  CoverLetterView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/10/24.
//

import SwiftUI

struct CoverLetterView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
  @State var myLetter: CoverLetter?
  @Binding var buttons: CoverLetterButtons

  var body: some View {
    if let jobApp = jobAppStore.selectedApp {
      if let res = jobApp.selectedRes {
        CoverLetterContentView(
          myLetter: Binding(
            get: { loadOrCreateLetter(letter: myLetter, jobApp: jobApp) },
            set: { myLetter = $0 }
          ),
          res: Binding(
            get: { res },
            set: { jobApp.selectedRes = $0 }
          ),
          jobApp: jobApp,
          buttons: $buttons // Use `$buttons` to pass the binding
        )
      }
    }
    Text("foo")
  }


  func loadOrCreateLetter(letter: CoverLetter?, jobApp: JobApp) -> CoverLetter {
    if let letter = letter {
      return letter
    }
    if jobApp.coverLetters.isEmpty {
      return coverLetterStore.create(jobApp: jobApp)
    }
    else {
      return jobApp.coverLetters.last!
    }
  }
}

struct CoverLetterContentView: View {
  @Environment(CoverRefStore.self) private var coverRefStore: CoverRefStore

  @Binding var myLetter: CoverLetter
  @Binding var res: Resume
  @Bindable var jobApp: JobApp
  @Binding var buttons: CoverLetterButtons
  var body: some View {
    VStack{
      Picker(
        "Load existing cover letter",
        selection: $myLetter
      ) {
        Text("None").tag(nil as CoverLetter?)
        ForEach($jobApp.coverLetters, id: \.self) { resume in
          Text("Generated at \(myLetter.modDate)")
            .tag(myLetter)
            .help("Select a cover letter to customize")
        }
      }
        Text("AI generated text at \(myLetter.modDate)").font(.caption).italic()
        Text(myLetter.content).fixedSize(horizontal: false, vertical: true)
    }.inspector(isPresented: $buttons.showInspector){
      CoverRefView(
        coverLetter: myLetter,
        backgroundFacts: coverRefStore.backgroundRefs,
        writingSamples: coverRefStore.writingSamples
      )
    }
  }
}
