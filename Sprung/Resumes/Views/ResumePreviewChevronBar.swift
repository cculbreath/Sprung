//
//  ResumePreviewChevronBar.swift
//  Sprung
//
//  Narrow vertical chevron strip for toggling PDF preview visibility.
//  Bidirectional: shows opposite chevrons based on current state.
//

import SwiftUI

/// Narrow vertical chevron bar that toggles PDF preview visibility
struct ResumePreviewChevronBar: View {
    @Binding var pdfPreviewVisible: Bool

    @State private var isHovered = false

    private let barWidth: CGFloat = 16

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                pdfPreviewVisible.toggle()
            }
        } label: {
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: chevronSymbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isHovered ? .primary : .tertiary)
                Spacer()
            }
            .frame(width: barWidth)
            .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(pdfPreviewVisible ? "Hide PDF preview" : "Show PDF preview")
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(width: 1)
        }
    }

    private var chevronSymbol: String {
        // When preview is visible, show right chevron to collapse (hide)
        // When preview is hidden, show left chevron to expand (show)
        pdfPreviewVisible ? "chevron.compact.right" : "chevron.compact.left"
    }
}
