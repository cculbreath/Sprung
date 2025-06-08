// PhysCloudResume/App/Views/SidebarToolbarView.swift

import SwiftUI

struct SidebarToolbarView: View {
    // Bindings for the state controlled by the parent (ContentView/SidebarView)
    @Binding var showSlidingList: Bool

    var body: some View {
        // Push buttons to the right
        Spacer()
        
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
    }
}