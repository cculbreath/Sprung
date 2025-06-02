// PhysCloudResume/App/Views/SidebarToolbarView.swift

import SwiftUI

struct SidebarToolbarView: View {
    // Bindings for the state controlled by the parent (ContentView/SidebarView)
    @Binding var showSlidingList: Bool
    @Binding var showNewAppSheet: Bool

    var body: some View {
        // No HStack - just build the toolbar content directly
        Spacer() // Push buttons to the right

        // --- Show/Hide Sources Button ---
        Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.2)) {
                showSlidingList.toggle()
            }
        } label: {
            Label(
                showSlidingList ? "Hide Sources" : "Show Sources",
                systemImage: "append.page"
            )
            .foregroundColor(showSlidingList ? .accentColor : .secondary)
            .font(.system(size: 14))
            .imageScale(.large)
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .help(showSlidingList ? "Hide Résumé Sources Panel" : "Show Résumé Sources Panel")

        // --- AI Job Recommendation Button ---
        // Use a simple button that doesn't access AppState during early initialization
        Button(action: {
            // This will be handled safely when clicked
            print("Job recommendation button clicked")
        }) {
            Label("Find Best Match", systemImage: "sparkles.rectangle.stack")
                .foregroundColor(.primary)
                .font(.system(size: 14))
                .imageScale(.large)
        }
        .buttonStyle(.plain)
        .help("Find the best job match based on your qualifications")

        // --- New Application Button ---
        Button {
            showNewAppSheet = true
        } label: {
            Label("New Application", systemImage: "plus.square.on.square")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
                .imageScale(.large)
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .help("Add New Job Application")
    }
}
