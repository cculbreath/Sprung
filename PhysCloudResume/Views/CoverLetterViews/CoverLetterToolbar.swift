import SwiftUI

@ToolbarContentBuilder
func CoverLetterToolbar(
  buttons: Binding<CoverLetterButtons>,
  jobApp: JobApp?,
  resume: Binding<Resume?>
) -> some ToolbarContent {

  ToolbarItem(placement: .automatic) {
    CoverLetterAiView(
      selRes: resume,
      buttons: buttons
    ).onAppear{print("foo")}

  }
  ToolbarItem(placement: .automatic) {
    Button(action: {
      buttons.wrappedValue.showInspector.toggle()
    }) {
      Label("Toggle Inspector", systemImage: "sidebar.right")
    }.onAppear{print("Toolbar Cover Letter")}
  }
}
