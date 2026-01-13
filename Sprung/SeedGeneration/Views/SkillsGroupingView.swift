//
//  SkillsGroupingView.swift
//  Sprung
//
//  Preview of generated skill groupings.
//

import SwiftUI

/// View for previewing generated skill groups
struct SkillsGroupingView: View {
    let groups: [SkillGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            groupsList
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skill Categories")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your skills have been organized into \(groups.count) categories for your resume.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Groups List

    private var groupsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(groups, id: \.name) { group in
                    SkillGroupCard(group: group)
                }
            }
            .padding()
        }
    }
}

// MARK: - Skill Group Card

private struct SkillGroupCard: View {
    let group: SkillGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.name)
                    .font(.headline)

                Spacer()

                Text("\(group.keywords.count) skills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(group.keywords, id: \.self) { skill in
                    SkillTag(name: skill)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Skill Tag

private struct SkillTag: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.blue.opacity(0.1), in: Capsule())
            .foregroundStyle(.blue)
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, placement) in result.placements.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY + placement.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, placements: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var placements: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            placements.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (
            size: CGSize(width: maxX, height: currentY + lineHeight),
            placements: placements
        )
    }
}
