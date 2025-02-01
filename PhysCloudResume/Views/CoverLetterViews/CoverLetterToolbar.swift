import SwiftUI

func CoverLetterToolbar(
    buttons: Binding<CoverLetterButtons>,
    refresh: Binding<Bool>
) -> some View {
    return HStack {
        CoverLetterAiView(
            buttons: buttons,
            refresh: refresh
        ).onAppear { print("foo") }

        // Use .primaryAction for right-side placement on macOS

        Button(action: {
            buttons.wrappedValue.showInspector.toggle()
        }) {
            Label("Toggle Inspector", systemImage: "sidebar.right")
        }
        .onAppear { print("Toolbar Cover Letter") }
    }
}
