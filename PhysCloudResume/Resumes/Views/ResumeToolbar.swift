// PhysCloudResume/Resumes/Views/ResumeToolbar.swift
import SwiftUI

@ToolbarContentBuilder
func resumeToolbarContent(buttons: Binding<ResumeButtons>, selectedResume: Binding<Resume?>) -> some ToolbarContent {
    ToolbarItem(placement: .primaryAction) { // Group all items into a single ToolbarItem with .primaryAction
        HStack(spacing: 8) { // Use an HStack to group the buttons for consistent alignment
            // AI resume enhancement feature
            if selectedResume.wrappedValue?.rootNode != nil {
                AiFunctionView(res: selectedResume)
            } else {
                Text(" ").opacity(0)
                // Optional: Add a placeholder or empty view if no resume is selected
                // to help maintain layout consistency, though often omitting it is fine.
                // For example: Text(" ").opacity(0)
            }

            // AI resume review feature
            Button {
                buttons.wrappedValue.showResumeReviewSheet.toggle()
            } label: {
                Label("Review Resume", systemImage: "character.magnify") // Or your current icon, e.g., "doc.text.viewfinder"
            }
            .help("AI Resume Review")
            .disabled(selectedResume.wrappedValue == nil)
            .sheet(isPresented: Binding(
                get: { buttons.wrappedValue.showResumeReviewSheet },
                set: { buttons.wrappedValue.showResumeReviewSheet = $0 }
            )) {
                ResumeReviewSheet(selectedResume: selectedResume)
            }

            // Resume inspector toggle
            Button(action: {
                buttons.wrappedValue.showResumeInspector.toggle()
            }) {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            // Removed .onAppear as it's not directly related to the toolbar structure itself.
        }
    }
}
