import SwiftUI

struct CoverRefView: View {
  @State var backgroundFacts: [CoverRef]
  @State var writingSamples: [CoverRef]
  @State private var showAddBackgroundFactSheet = false
  @State private var showAddWritingSampleSheet = false
  @Environment(CoverRefStore.self) var coverRefStore: CoverRefStore
  @Environment(CoverLetterStore.self) var coverLetterStore: CoverLetterStore

  var body: some View {
    @Bindable var coverLetterStore = coverLetterStore
    if let cL = coverLetterStore.cL {
      List {
        Section("Background Facts") {
          ForEach(backgroundFacts, id: \.id) { fact in
            HStack {
              Toggle(isOn: Binding<Bool>(
                get: { cL.enabledRefs.contains(where: { $0.id == fact.id }) },
                set: { isEnabled in
                  if isEnabled {
                    if !cL.enabledRefs.contains(where: { $0.id == fact.id }) {
                      cL.enabledRefs.append(fact)
                    }
                  } else {
                    cL.enabledRefs.removeAll { $0.id == fact.id }
                  }
                }
              )) {
                Text(fact.content)
              }
            }
          }
          Button(action: {
            showAddBackgroundFactSheet.toggle()
          }) {
            Label("Add Background Fact", systemImage: "plus")
          }
        }
        .sheet(isPresented: $showAddBackgroundFactSheet) {
          AddCoverRefForm(
            type: .backgroundFact,
            coverLetter: cL,
            backgroundFacts: $backgroundFacts,
            writingSamples: $writingSamples,
            showMe: $showAddBackgroundFactSheet
          )
        }

        Section("Writing Samples") {
          ForEach(writingSamples, id: \.id) { sample in
            HStack {
              Toggle(isOn: Binding<Bool>(
                get: { cL.enabledRefs.contains(where: { $0.id == sample.id }) },
                set: { isEnabled in
                  if isEnabled {
                    if !cL.enabledRefs.contains(where: { $0.id == sample.id }) {
                      cL.enabledRefs.append(sample)
                    }
                  } else {
                    cL.enabledRefs.removeAll { $0.id == sample.id }
                  }
                }
              )) {
                Text(sample.name)
              }
            }
          }
          Button(action: {
            showAddWritingSampleSheet.toggle()
          }) {
            Label("Add Writing Sample", systemImage: "plus")
          }
        }
        .sheet(isPresented: $showAddWritingSampleSheet) {
          AddCoverRefForm(
            type: .writingSample,
            coverLetter: cL,
            backgroundFacts: $backgroundFacts,
            writingSamples: $writingSamples,
            showMe: $showAddWritingSampleSheet
          )
        }
      }}
  }
}
