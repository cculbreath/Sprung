import SwiftUI

/// Tab content showing approved skills grouped by category.
/// Pending skills are reviewed in the Interview tab; approved skills appear here.
struct SkillsTabContent: View {
    let coordinator: OnboardingInterviewCoordinator

    @State private var expandedSkillIds: Set<UUID> = []
    @State private var expandedCategories: Set<SkillCategory> = Set(SkillCategory.allCases)

    /// Approved skills (from SwiftData store)
    private var approvedSkills: [Skill] {
        coordinator.skillStore.approvedSkills
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !approvedSkills.isEmpty {
                skillsListView(skills: approvedSkills)
            } else {
                emptyState
            }
        }
    }

    @ViewBuilder
    private func skillsListView(skills: [Skill]) -> some View {
        let grouped = Dictionary(grouping: skills, by: { $0.category })
        let sortedCategories = SkillCategory.allCases.filter { grouped[$0] != nil }

        ForEach(sortedCategories, id: \.self) { category in
            if let categorySkills = grouped[category] {
                categorySection(category: category, skills: categorySkills)
            }
        }
    }

    @ViewBuilder
    private func categorySection(category: SkillCategory, skills: [Skill]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Category header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedCategories.contains(category) {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: expandedCategories.contains(category) ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text(category.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("(\(skills.count))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            if expandedCategories.contains(category) {
                ForEach(skills.sorted { $0.proficiency.sortOrder < $1.proficiency.sortOrder }) { skill in
                    SkillRow(
                        skill: skill,
                        isExpanded: expandedSkillIds.contains(skill.id),
                        showDeleteButton: true,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedSkillIds.contains(skill.id) {
                                    expandedSkillIds.remove(skill.id)
                                } else {
                                    expandedSkillIds.insert(skill.id)
                                }
                            }
                        },
                        onDelete: {
                            coordinator.skillStore.delete(skill)
                        }
                    )
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Skills Extracted",
            systemImage: "wrench.and.screwdriver",
            description: Text("Skills will be extracted from uploaded documents during the interview.")
        )
        .frame(height: 180)
    }
}

/// Row view for a single skill with expandable details.
private struct SkillRow: View {
    let skill: Skill
    let isExpanded: Bool
    let showDeleteButton: Bool
    let onToggleExpand: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 8) {
                // Clickable expand area
                Button(action: onToggleExpand) {
                    HStack(spacing: 8) {
                        // Expand/collapse indicator
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 10)

                        // Skill name
                        Text(skill.canonical)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        // Proficiency badge
                        proficiencyBadge

                        // Evidence count
                        if !skill.evidence.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "doc.text")
                                    .font(.caption2)
                                Text("\(skill.evidence.count)")
                                    .font(.caption2.monospacedDigit())
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Delete button (only when ready for approval)
                if showDeleteButton {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Remove this skill")
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)

            // Expanded details
            if isExpanded {
                expandedContent
                    .padding(.leading, 26)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var proficiencyBadge: some View {
        Text(skill.proficiency.rawValue.capitalized)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(proficiencyColor.opacity(0.15))
            )
            .foregroundStyle(proficiencyColor)
    }

    private var proficiencyColor: Color {
        switch skill.proficiency {
        case .expert: return .green
        case .proficient: return .blue
        case .familiar: return .orange
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ATS Variants
            if !skill.atsVariants.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ATS Variants")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 4) {
                        ForEach(skill.atsVariants, id: \.self) { variant in
                            Text(variant)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.secondary.opacity(0.1))
                                )
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Evidence
            if !skill.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Evidence")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(skill.evidence, id: \.documentId) { evidence in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: evidenceIcon(for: evidence.strength))
                                .font(.caption2)
                                .foregroundStyle(evidenceColor(for: evidence.strength))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(evidence.context)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                Text(evidence.location)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Last used
            if let lastUsed = skill.lastUsed {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("Last used: \(lastUsed)")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func evidenceIcon(for strength: EvidenceStrength) -> String {
        switch strength {
        case .primary: return "star.fill"
        case .supporting: return "star.leadinghalf.filled"
        case .mention: return "star"
        }
    }

    private func evidenceColor(for strength: EvidenceStrength) -> Color {
        switch strength {
        case .primary: return .yellow
        case .supporting: return .orange
        case .mention: return .secondary
        }
    }
}

/// Simple flow layout for tags/chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .init(frame.size))
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), frames)
    }
}
