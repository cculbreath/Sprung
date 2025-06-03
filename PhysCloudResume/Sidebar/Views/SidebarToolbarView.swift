// PhysCloudResume/App/Views/SidebarToolbarView.swift

import SwiftUI

struct SidebarToolbarView: View {
    // Bindings for the state controlled by the parent (ContentView/SidebarView)
    @Binding var showSlidingList: Bool
    @Binding var showNewAppSheet: Bool

    var body: some View {
        // Push buttons to the right
        Spacer()
        
        HStack(spacing: 16) {
            // --- Show Sources Button ---
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.2)) {
                    showSlidingList.toggle()
                }
            } label: {
                Image(systemName: "newspaper")
                    .font(.system(size: 18))
                    .foregroundColor(showSlidingList ? .accentColor : .primary)
            }
            .buttonStyle(.plain)
            .help("Show Sources")

            // --- AI Job Recommendation Button ---
            RecommendJobButton()

            // --- New Application Button ---
            Button {
                showNewAppSheet = true
            } label: {
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .help("New Job Application")
        }
    }
}