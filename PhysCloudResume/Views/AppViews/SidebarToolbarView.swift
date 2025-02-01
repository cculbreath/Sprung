// SidebarToolbarView.swift

import SwiftUI

struct SidebarToolbarView: ToolbarContent {
    @Binding var showNewAppSheet: Bool
    @Binding var showSlidingList: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) { // macOS-compatible placement
            Button(action: {
                showNewAppSheet = true
            }) {
                Label("New Application", systemImage: "plus.square.on.square")
            }

            Button(action: {
                withAnimation {
                    showSlidingList.toggle()
                }
            }) {
                Label(
                    showSlidingList ? "Hide Additional List" : "Show Additional List",
                    systemImage: "append.page"
                )
                .foregroundColor(showSlidingList ? .accentColor : .primary)
            }
            Spacer() // ✅ This forces items to align to the trailing side of the sidebar
        }
    }
}
