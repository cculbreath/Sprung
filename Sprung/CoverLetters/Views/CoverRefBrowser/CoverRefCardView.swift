//
//  CoverRefCardView.swift
//  Sprung
//
//
import SwiftUI

/// Individual card view for displaying a CoverRef in the browser
struct CoverRefCardView: View {
    let coverRef: CoverRef
    let isTopCard: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var typeColor: Color {
        switch coverRef.type {
        case .backgroundFact:
            return .blue
        case .writingSample:
            return .purple
        case .voicePrimer:
            return .teal
        }
    }

    private var typeIcon: String {
        switch coverRef.type {
        case .backgroundFact:
            return "info.circle.fill"
        case .writingSample:
            return "doc.text.fill"
        case .voicePrimer:
            return "waveform.and.person.filled"
        }
    }

    private var typeLabel: String {
        switch coverRef.type {
        case .backgroundFact:
            return "Background Fact"
        case .writingSample:
            return "Writing Sample"
        case .voicePrimer:
            return "Voice Primer"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with type badge
            HStack {
                // Type badge
                HStack(spacing: 4) {
                    Image(systemName: typeIcon)
                        .font(.caption)
                    Text(typeLabel)
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(typeColor.opacity(0.15))
                .foregroundStyle(typeColor)
                .clipShape(Capsule())

                Spacer()

                // Action buttons (visible on hover or if top card)
                if isHovering || isTopCard {
                    HStack(spacing: 8) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit")

                        Button(action: onDelete) {
                            Image(systemName: "trash.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                    .transition(.opacity)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // Title
            Text(coverRef.name)
                .font(.headline)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)

            // Content preview
            ScrollView {
                Text(coverRef.content)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            // Footer with enabled status
            HStack {
                if coverRef.enabledByDefault {
                    Label("Enabled by default", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isTopCard ? typeColor.opacity(0.5) : Color(nsColor: .separatorColor), lineWidth: isTopCard ? 2 : 1)
        )
        .shadow(color: .black.opacity(isTopCard ? 0.2 : 0.1), radius: isTopCard ? 12 : 6, y: isTopCard ? 6 : 3)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}
