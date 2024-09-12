import SwiftUI

struct AddCoverRefForm: View {
  @Environment(CoverRefStore.self) private var coverRefStore: CoverRefStore
  @State private var newCoverRefName = ""
  @State private var newCoverRefContent = ""
  @State private var newCoverRefEnabledByDefault = false
  var type: CoverRefType
  @Bindable var coverLetter: CoverLetter
  @Binding var backgroundFacts: [CoverRef]
  @Binding var writingSamples: [CoverRef]
  @Binding var showMe: Bool

  var body: some View {
    NavigationView {
      Form {
        TextField("Name", text: $newCoverRefName)
        TextField("Content", text: $newCoverRefContent)
        Toggle("Enabled by Default", isOn: $newCoverRefEnabledByDefault)

        Button("Add") {
          let newCoverRef = CoverRef(
            name: newCoverRefName,
            content: newCoverRefContent,
            enabledByDefault: newCoverRefEnabledByDefault,
            type: type
          )

          if type == .backgroundFact {
            backgroundFacts.append(newCoverRef)
          } else if type == .writingSample {
            writingSamples.append(newCoverRef)
          }

          let newRef = coverRefStore.addCoverRef(newCoverRef)
          coverLetter.enabledRefs.append(newRef)
          resetForm()
        }
      }
      .navigationTitle("Add \(type == .backgroundFact ? "Background Fact" : "Writing Sample")")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismissForm()
          }
        }
      }
    }
  }

  private func resetForm() {
    newCoverRefName = ""
    newCoverRefContent = ""
    newCoverRefEnabledByDefault = false
  }

  private func dismissForm() {

      showMe.toggle()



  }
}
