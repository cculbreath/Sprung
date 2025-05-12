// PhysCloudResume/CoverLetters/Views/CoverLetterToolbar.swift
import SwiftUI

/// Cover Letter AI View Provider to ensure we only create one instance
@MainActor
class CoverLetterAiViewProvider: ObservableObject {
    static let shared = CoverLetterAiViewProvider()
    private var instance: CoverLetterAiView? = nil

    private init() {}

    func getView(buttons: Binding<CoverLetterButtons>, refresh: Binding<Bool>) -> CoverLetterAiView {
        if let existingView = instance {
            return existingView
        } else {
            let newView = CoverLetterAiView(
                buttons: buttons,
                refresh: refresh,
                isNewConversation: true
            )
            instance = newView
            return newView
        }
    }
}

/// Cover Letter Toolbar with proper view lifecycle management
@MainActor
@ToolbarContentBuilder
func CoverLetterToolbar(
    buttons: Binding<CoverLetterButtons>,
    refresh: Binding<Bool>
) -> some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
        HStack(spacing: 8) {
            // Get the existing view from our provider - this avoids creating it during rendering
            CoverLetterAiViewProvider.shared.getView(buttons: buttons, refresh: refresh)

            Button(action: {
                buttons.wrappedValue.showInspector.toggle()
            }) {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle Inspector Panel")
        }
    }
}
