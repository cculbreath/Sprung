//
//  ResRefRowView.swift
//  Sprung
//
//  Row view for displaying a knowledge card in the list.
//  Shows card type indicator for fact-based cards.
//

import SwiftUI

struct ResRefRowView: View {
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    @State var sourceNode: ResRef
    @State private var isButtonHovering = false
    @State private var isEditSheetPresented: Bool = false

    var body: some View {
        @Bindable var resRefStore = resRefStore
        HStack(spacing: 12) {
            // Toggle
            Toggle("", isOn: $sourceNode.enabledByDefault)
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()

            // Card type icon (for fact-based cards)
            if sourceNode.isFactBasedCard {
                let typeInfo = sourceNode.cardTypeDisplay
                Image(systemName: typeInfo.icon)
                    .foregroundStyle(cardTypeColor)
                    .frame(width: 20)
            }

            // Card info
            VStack(alignment: .leading, spacing: 2) {
                Text(sourceNode.name)
                    .foregroundColor(sourceNode.enabledByDefault ? .primary : .secondary)
                    .lineLimit(1)

                // Subtitle with metadata
                if sourceNode.isFactBasedCard {
                    HStack(spacing: 8) {
                        if let org = sourceNode.organization, !org.isEmpty {
                            Text(org)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let period = sourceNode.timePeriod, !period.isEmpty {
                            Text(period)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        // Stats
                        let bulletCount = sourceNode.suggestedBullets.count
                        let techCount = sourceNode.technologies.count
                        if bulletCount > 0 || techCount > 0 {
                            Spacer()
                            if bulletCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "list.bullet")
                                        .font(.caption2)
                                    Text("\(bulletCount)")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.tertiary)
                            }
                            if techCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "cpu")
                                        .font(.caption2)
                                    Text("\(techCount)")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .onTapGesture {
                isEditSheetPresented = true
            }
            .sheet(isPresented: $isEditSheetPresented) {
                ResRefFormView(
                    isSheetPresented: $isEditSheetPresented,
                    existingResRef: sourceNode
                )
            }

            Spacer()

            // Delete button
            Button(action: {
                resRefStore.deleteResRef(sourceNode)
            }) {
                Image(systemName: "trash.fill")
                    .foregroundColor(isButtonHovering ? .red : .gray)
                    .font(.system(size: 15))
                    .padding(2)
                    .background(isButtonHovering ? Color.red.opacity(0.3) : Color.gray.opacity(0.3))
                    .cornerRadius(5)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(4)
            .onHover { hovering in
                isButtonHovering = hovering
            }
        }
        .padding(.vertical, 5)
    }

    private var cardTypeColor: Color {
        switch sourceNode.cardType?.lowercased() {
        case "employment", "job":
            return .blue
        case "project":
            return .orange
        case "skill":
            return .purple
        case "education":
            return .green
        case "achievement":
            return .yellow
        default:
            return .secondary
        }
    }
}
