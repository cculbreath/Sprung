//
//  FontSizePanelView.swift
//  Sprung
//
//  Panel for adjusting template font sizes.
//  Always expanded within the Styling drawer.
//

import SwiftData
import SwiftUI

struct FontSizePanelView: View {
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Font Sizes")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 8)

            // Font size controls
            let nodes = vm.fontSizeNodes
            if nodes.isEmpty {
                Text("No font sizes available")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .padding(12)
            } else {
                VStack(spacing: 4) {
                    ForEach(nodes, id: \.id) { node in
                        FontNodeView(node: node)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
