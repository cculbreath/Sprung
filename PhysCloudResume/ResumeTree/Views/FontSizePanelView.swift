//
//  FontSizePanelView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

import SwiftData
import SwiftUI

struct FontSizePanelView: View {
    @State var isExpanded: Bool = false
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    var body: some View {
        HStack {
            ToggleChevronView(isExpanded: $isExpanded,)
            Text("Font Sizes")
                .font(.headline)
        }
        .onTapGesture {
            withAnimation { isExpanded.toggle() }
        }
        .cornerRadius(5)
        .padding(.vertical, 2)

        if isExpanded { 
            VStack {
                // Safely access fontSizeNodes to avoid CoreData faulting issues
                if let resume = jobAppStore.selectedApp?.selectedRes {
                    // Try to access fontSizeNodes with error handling
                    let nodes = resume.fontSizeNodes.sorted { $0.index < $1.index }
                    ForEach(nodes, id: \.id) { node in
                        FontNodeView(node: node)
                    }
                } else {
                    Text("No font sizes available")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding(.trailing, 16) // Avoid overlap on trailing side.
        }
    }
}
