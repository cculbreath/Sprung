import SwiftUI

@ToolbarContentBuilder
func CoverLetterToolbar(buttons: Binding<CoverLetterButtons>) -> some ToolbarContent {
  ToolbarItem(placement: .automatic) {
    Button(action: {
      buttons.wrappedValue.showInspector.toggle()
    }) {
      Label("Toggle Inspector", systemImage: "sidebar.right")
    }
  }
}
