//
//  TitleSetEditorView.swift
//  Sprung
//
//  Editor view for managing pre-validated title sets.
//  Allows favoriting and viewing identity vocabulary.
//

import SwiftUI

struct TitleSetEditorView: View {
    @Environment(InferenceGuidanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var titleSets: [TitleSet] = []
    @State private var vocabulary: [IdentityTerm] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if vocabulary.isEmpty && titleSets.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if !vocabulary.isEmpty {
                                vocabularySection
                            }

                            if !titleSets.isEmpty {
                                titleSetsSection
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Title Sets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                titleSets = store.titleSets()
                vocabulary = store.identityVocabulary()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Title Sets")
                .font(.headline)
            Text("Title sets are generated during onboarding based on your career documents.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Identity Vocabulary")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(vocabulary) { term in
                    TermChip(term: term)
                }
            }
        }
    }

    private var titleSetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Title Sets")
                    .font(.headline)
                Spacer()
                Text("\(titleSets.filter(\.isFavorite).count) favorited")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(titleSets) { set in
                    TitleSetRow(
                        set: set,
                        onToggleFavorite: {
                            store.toggleTitleSetFavorite(set.id)
                            titleSets = store.titleSets()
                        }
                    )
                }
            }
        }
    }
}

struct TermChip: View {
    let term: IdentityTerm

    var body: some View {
        HStack(spacing: 4) {
            Text(term.term)
                .font(.subheadline)

            Text(String(format: "%.0f%%", term.evidenceStrength * 100))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(strengthColor.opacity(0.15))
        .foregroundStyle(strengthColor)
        .cornerRadius(6)
    }

    private var strengthColor: Color {
        if term.evidenceStrength >= 0.8 {
            return .green
        } else if term.evidenceStrength >= 0.6 {
            return .blue
        } else {
            return .orange
        }
    }
}

struct TitleSetRow: View {
    let set: TitleSet
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleFavorite) {
                Image(systemName: set.isFavorite ? "star.fill" : "star")
                    .foregroundColor(set.isFavorite ? .yellow : .gray)
            }
            .buttonStyle(.plain)

            Text(set.displayString)
                .font(.body)

            Spacer()

            Text(set.emphasis.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(emphasisColor.opacity(0.15))
                .foregroundStyle(emphasisColor)
                .cornerRadius(4)

            if !set.suggestedFor.isEmpty {
                Text(set.suggestedFor.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private var emphasisColor: Color {
        switch set.emphasis {
        case .technical: return .blue
        case .research: return .purple
        case .leadership: return .orange
        case .balanced: return .green
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, proposal: proposal).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let result = layout(sizes: sizes, proposal: proposal)

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    private func layout(sizes: [CGSize], proposal: ProposedViewSize) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for size in sizes {
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
