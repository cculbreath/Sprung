import SwiftUI

struct CoverRefView: View {
  @Bindable var coverLetter: CoverLetter
  @State var backgroundFacts: [CoverRef]
  @State var writingSamples: [CoverRef]
  @State private var showAddBackgroundFactSheet = false
  @State private var showAddWritingSampleSheet = false
  @Environment(CoverRefStore.self)  var coverRefStore: CoverRefStore

  var body: some View {
    List {
      Section("Background Facts") {
        ForEach($backgroundFacts, id: \.self) { fact in
          HStack {
            Toggle(isOn: Binding<Bool>(
              get: { $coverLetter.wrappedValue.enabledRefs.contains(fact.wrappedValue) },
              set: { isEnabled in
                if isEnabled {
                  if !$coverLetter.wrappedValue.enabledRefs.contains(fact.wrappedValue) {
                    $coverLetter.wrappedValue.enabledRefs.append(fact.wrappedValue)
                  }
                } else {
                  $coverLetter.wrappedValue.enabledRefs.removeAll { $0 == fact.wrappedValue }
                }
              }
            )) {
              Text(fact.wrappedValue.content)
            }
          }
        }
        Button(action: {
          $showAddBackgroundFactSheet.wrappedValue.toggle()
        }) {
          Label("Add Background Fact", systemImage: "plus")
        }
      }
      .sheet(isPresented: $showAddBackgroundFactSheet) {
        AddCoverRefForm(type: .backgroundFact, coverLetter: coverLetter, backgroundFacts: $backgroundFacts, writingSamples: $writingSamples, showMe: $showAddBackgroundFactSheet)
      }

      Section("Writing Samples") {
        ForEach(writingSamples, id: \.self) { sample in
          HStack {
            Toggle(isOn: Binding<Bool>(
              get: { coverLetter.enabledRefs.contains(sample) },
              set: { isEnabled in
                if isEnabled {
                  if !coverLetter.enabledRefs.contains(sample) {
                    coverLetter.enabledRefs.append(sample)
                  }
                } else {
                  coverLetter.enabledRefs.removeAll { $0 == sample }
                }
              }
            )) {
              Text(sample.content)
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
        AddCoverRefForm(type: .writingSample, coverLetter: coverLetter, backgroundFacts: $backgroundFacts, writingSamples: $writingSamples, showMe: $showAddWritingSampleSheet)
      }
    }
  }
}
