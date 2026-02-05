//
//  TargetingPlanReviewView.swift
//  Sprung
//
//  Review and edit UI for the strategic targeting plan.
//  Displayed after plan generation and before parallel field generation.
//  User edits persist back into the TargetingPlan struct.
//

import SwiftUI

// MARK: - Main Review View

struct TargetingPlanReviewView: View {
    @Binding var plan: TargetingPlan
    let onApprove: (TargetingPlan) -> Void
    let onRegenerate: () -> Void
    let isRegenerating: Bool

    @State private var newTheme: String = ""

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    narrativeArcSection
                    emphasisThemesSection
                    workEntryGuidanceSection
                    lateralConnectionsSection
                    identifiedGapsSection
                    prioritizedSkillsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            Divider()

            footerView
        }
        .frame(minWidth: 700, idealWidth: 850, maxWidth: 950)
        .frame(minHeight: 500, idealHeight: 700, maxHeight: 850)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "target")
                .font(.system(size: 24))
                .foregroundStyle(.orange)

            Text("Strategic Targeting Plan")
                .font(.system(.title2, design: .rounded, weight: .semibold))

            Spacer()

            Text("Review and edit before generating")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Narrative Arc

    private var narrativeArcSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Narrative Arc", icon: "text.quote", color: .purple)

            Text("The overarching story this resume tells. Edit to refine the framing.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            TextEditor(text: $plan.narrativeArc)
                .font(.system(.body, design: .default))
                .frame(minHeight: 60, maxHeight: 120)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                )
        }
        .padding(12)
        .background(Color.purple.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Emphasis Themes

    private var emphasisThemesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Emphasis Themes", icon: "tag.fill", color: .blue)

            Text("Themes woven through all sections. Remove or add as needed.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(Array(plan.emphasisThemes.enumerated()), id: \.offset) { index, theme in
                    themeChip(theme: theme, index: index)
                }
            }

            HStack(spacing: 8) {
                TextField("Add a theme...", text: $newTheme)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onSubmit {
                        addTheme()
                    }

                Button {
                    addTheme()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(newTheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func themeChip(theme: String, index: Int) -> some View {
        HStack(spacing: 4) {
            Text(theme)
                .font(.system(.callout, design: .rounded))

            Button {
                plan.emphasisThemes.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.blue.opacity(0.1))
        .clipShape(Capsule())
    }

    private func addTheme() {
        let trimmed = newTheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        plan.emphasisThemes.append(trimmed)
        newTheme = ""
    }

    // MARK: - Work Entry Guidance

    private var workEntryGuidanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Work Entry Guidance", icon: "briefcase.fill", color: .green)

            Text("How each work entry should be framed for this application.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach(Array(plan.workEntryGuidance.enumerated()), id: \.element.id) { index, entry in
                workEntryCard(entry: entry, index: index)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func workEntryCard(entry: WorkEntryGuidance, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.entryIdentifier)
                .font(.system(.headline, design: .rounded, weight: .semibold))

            HStack(alignment: .top, spacing: 4) {
                Text("Lead with:")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)

                TextField("Lead angle", text: Binding(
                    get: { plan.workEntryGuidance[index].leadAngle },
                    set: { newValue in
                        let updated = WorkEntryGuidance(
                            entryIdentifier: entry.entryIdentifier,
                            leadAngle: newValue,
                            emphasis: entry.emphasis,
                            deEmphasis: entry.deEmphasis,
                            supportingCardIds: entry.supportingCardIds
                        )
                        plan.workEntryGuidance[index] = updated
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(.callout))
            }

            if !entry.emphasis.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text("Emphasize:")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)

                    Text(entry.emphasis.joined(separator: "; "))
                        .font(.system(.caption))
                        .foregroundStyle(.primary.opacity(0.8))
                }
            }

            if !entry.deEmphasis.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text("De-emphasize:")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)

                    Text(entry.deEmphasis.joined(separator: "; "))
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Lateral Connections

    private var lateralConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Lateral Connections", icon: "arrow.triangle.branch", color: .orange)

            Text("Non-obvious skill transfers. These are high-value insights. Dismiss any that don't resonate.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach(Array(plan.lateralConnections.enumerated()), id: \.element.id) { index, connection in
                lateralConnectionCard(connection: connection, index: index)
            }

            if plan.lateralConnections.isEmpty {
                Text("No lateral connections identified.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func lateralConnectionCard(connection: LateralConnection, index: Int) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(connection.sourceCardTitle)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .foregroundStyle(.orange)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text(connection.targetRequirement)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                }

                Text(connection.reasoning)
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                plan.lateralConnections.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Identified Gaps

    private var identifiedGapsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Identified Gaps", icon: "exclamationmark.triangle.fill", color: .red)

            Text("Gaps relative to job requirements. Informational — helps interpret the generated resume.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach(plan.identifiedGaps, id: \.self) { gap in
                HStack {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.6))

                    Text(gap)
                        .font(.system(.callout))
                }
            }

            if plan.identifiedGaps.isEmpty {
                Text("No significant gaps identified.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Prioritized Skills

    private var prioritizedSkillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Prioritized Skills", icon: "list.number", color: .teal)

            Text("Skills to feature prominently, ordered by importance for this role.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach(Array(plan.prioritizedSkills.enumerated()), id: \.offset) { index, skill in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.teal)
                        .frame(width: 20)

                    Text(skill)
                        .font(.system(.callout))
                }
            }

            if plan.prioritizedSkills.isEmpty {
                Text("No skills prioritized.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(Color.teal.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button {
                onRegenerate()
            } label: {
                HStack(spacing: 4) {
                    if isRegenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Regenerate")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRegenerating)

            Spacer()

            Button {
                onApprove(plan)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Approve & Generate")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRegenerating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)

            Text(title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
        }
    }
}

// MARK: - Flow Layout

/// Simple flow layout for tag/chip display.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
