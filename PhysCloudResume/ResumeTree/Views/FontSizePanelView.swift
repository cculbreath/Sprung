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
    @Binding var refresher: Bool
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    var body: some View {
        HStack {
            ToggleChevronView(isExpanded: $isExpanded, toggleAction: {
                withAnimation {
                    isExpanded.toggle()
                    if !isExpanded {
                        refresher.toggle()
                    }
                }
            })
            Text("Font Sizes")
                .font(.headline)
        }
        .cornerRadius(5)
        .padding(.vertical, 2)

        if isExpanded { VStack {
            ForEach(
                jobAppStore.selectedApp?.selectedRes?.fontSizeNodes.sorted { $0.index < $1.index } ?? [],
                id: \.self
            ) { node in
                FontNodeView(node: node, refresher: $refresher)
            }
        }
        .padding(.trailing, 16) // Avoid overlap on trailing side.
        .onAppear(perform: { for node in jobAppStore.selectedApp?.selectedRes?.fontSizeNodes ?? [] {}
            if jobAppStore.selectedApp?.selectedRes?.fontSizeNodes == nil { print("Ah fuk. empty") }
        })
        }
    }
}
