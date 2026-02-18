//
//  TitleSetBrowserRow.swift
//  Sprung
//
//  Row view for an approved title set in the browser panel with hover actions.
//

import SwiftUI

struct TitleSetBrowserRow: View {
    let titleSet: TitleSetRecord
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onLoad: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleSet.compactDisplayString)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            if let notes = titleSet.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Text(titleSet.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if isHovering {
                    Button(action: onLoad) {
                        Image(systemName: "arrow.up.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Load into generator")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.cyan.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.cyan.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }
}
