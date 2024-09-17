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
        // Custom "header" using Text for Background Facts
        Text("Background Facts")
          .font(.headline)
          .foregroundColor(.primary)
          .padding(.vertical, 5)
          .background(Color.clear).sheet(isPresented: $showAddBackgroundFactSheet) {
            AddCoverRefForm(type: .backgroundFact, coverLetter: cL, backgroundFacts: $backgroundFacts, writingSamples: $writingSamples, showMe: $showAddBackgroundFactSheet)
          } 

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
          .listRowBackground(Color.clear)  // Ensure row background is clear
        }

        Button(action: {
          showAddBackgroundFactSheet.toggle()
        }) {
          Label("Add Background Fact", systemImage: "plus")
        }
        .listRowBackground(Color.clear)  // Ensure button row background is clear

        // Custom "header" using Text for Writing Samples
        Text("Writing Samples")
          .font(.headline)
          .foregroundColor(.primary)
          .padding(.vertical, 5)
          .background(Color.clear).sheet(isPresented: $showAddWritingSampleSheet) {
            AddCoverRefForm(type: .writingSample, coverLetter: cL, backgroundFacts: $backgroundFacts, writingSamples: $writingSamples, showMe: $showAddWritingSampleSheet)
          }
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
          .listRowBackground(Color.clear)  // Ensure row background is clear
        }

        Button(action: {
          showAddWritingSampleSheet.toggle()
        }) {
          Label("Add Writing Sample", systemImage: "plus")
        }
        .listRowBackground(Color.clear)  // Ensure button row background is clear
      }
      .listStyle(PlainListStyle())  // Use plain list style
      .scrollContentBackground(.hidden)  // Ensure list background is hidden
      .background(Color.clear)  // Ensure overall background is clear

    }
  }
}
