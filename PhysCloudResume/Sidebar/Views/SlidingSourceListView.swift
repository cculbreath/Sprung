//
//  SlidingSourceListView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on .
//

import SwiftUI

import SwiftUI

struct SlidingSourceListView: View {
    @Binding var refresh: Bool
    var body: some View {
        ScrollView { // Enable scrolling when content overflows
            VStack {
                ResRefView()
                Divider()
                Divider()
                ResModelView(refresh: $refresh)
            }
            .padding(.horizontal, 0) // Remove any unintended padding
            .frame(maxWidth: .infinity) // Allow full width expansion
        }
        .frame(maxWidth: .infinity, maxHeight: 300, alignment: .bottom) // Restrict height
        .background(Color.white.opacity(0.6)) // Ensure it looks like a solid pane
        .overlay(
            Rectangle()
                .frame(height: 1) // Set height for the top border
                .foregroundColor(Color.black.opacity(0.4)), // Border color
            alignment: .top // Position at the top
        )
        .clipped() // Prevents overflow issues
    }
}
