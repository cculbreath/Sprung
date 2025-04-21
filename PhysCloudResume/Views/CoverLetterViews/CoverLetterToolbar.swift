import SwiftUI

func CoverLetterToolbar(
    buttons: Binding<CoverLetterButtons>,
    refresh: Binding<Bool>
) -> some View {
    return HStack {
        CoverLetterAiView(
            buttons: buttons,
            refresh: refresh
        )

        // Use .primaryAction for right-side placement on macOS
        // Edit/Preview toggle button (disabled for ungenerated drafts)
        Button(action: {
            buttons.wrappedValue.isEditing.toggle()
        }) {
            let editing = buttons.wrappedValue.isEditing
            Label(editing ? "Preview" : "Edit",
                  systemImage: editing ? "doc.text.viewfinder" : "pencil")
        }
        .disabled(!buttons.wrappedValue.canEdit)

        Button(action: {
            buttons.wrappedValue.showInspector.toggle()
        }) {
            Label("Toggle Inspector", systemImage: "sidebar.right")
        }
        .onAppear { print("Toolbar Cover Letter") }
    }
}
