// PhysCloudResume/CoverLetters/Views/CoverLetterToolbar.swift
import SwiftUI

func CoverLetterToolbar(
    buttons: Binding<CoverLetterButtons>,
    refresh: Binding<Bool>
) -> some View {
    return HStack {
        Spacer() // Added Spacer to push content to the trailing edge

        CoverLetterAiView(
            buttons: buttons,
            refresh: refresh
        )

        Button(action: {
            buttons.wrappedValue.showInspector.toggle()
        }) {
            Label("Toggle Inspector", systemImage: "sidebar.right")
        }
        .onAppear { print("Toolbar Cover Letter") }
    }
}
