// PhysCloudResume/CoverLetters/Views/CoverLetterToolbar.swift
import SwiftUI
import Observation

/// Cover Letter AI View Provider to ensure we only create one instance
@MainActor
@Observable
class CoverLetterAiViewProvider {
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
    ToolbarItem(placement: .automatic) {
        HStack(spacing: 8) {
            // Get the existing view from our provider - this avoids creating it during rendering
            CoverLetterAiViewProvider.shared.getView(buttons: buttons, refresh: refresh)
            
            // Batch generation button
            Button(action: {
                buttons.wrappedValue.showBatchGeneration = true
            }) {
                Label("Batch Generate", systemImage: "square.stack.3d.up.fill")
            }
            .help("Generate cover letters with multiple models")
            
            // Cover Letter References button
            CoverLetterReferencesButton()

        }
    }
}

/// Button that shows cover letter references in a popover
struct CoverLetterReferencesButton: View {
    @State private var showReferences = false
    
    var body: some View {
        Button(action: {
            showReferences.toggle()
        }) {
            Label("References", systemImage: "doc.text.magnifyingglass")
        }
        .help("Manage cover letter references")
        .popover(isPresented: $showReferences) {
            CoverLetterRefManagementView()
        }
    }
}
