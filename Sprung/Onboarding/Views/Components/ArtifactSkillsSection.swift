import SwiftUI

/// Displays approved/read-only skills extracted from an artifact, grouped by category
/// in flow-layout badge rows, with an optional regen button.
struct ArtifactSkillsSection: View {
    let skills: [Skill]
    let onRegenSkills: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.purple)
                Text("Skills (\(skills.count))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let regenAction = onRegenSkills {
                    Button {
                        regenAction()
                    } label: {
                        Image(systemName: "arrow.trianglehead.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Regenerate skills for this artifact")
                }
            }

            // Skills grouped by category
            let grouped = Dictionary(grouping: skills) { $0.category }
            ForEach(SkillCategoryUtils.sortedCategories(from: skills), id: \.self) { category in
                if let categorySkills = grouped[category], !categorySkills.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)

                        FlowStack(spacing: 4) {
                            ForEach(categorySkills.prefix(10), id: \.canonical) { skill in
                                skillBadge(skill)
                            }
                            if categorySkills.count > 10 {
                                Text("+\(categorySkills.count - 10)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func skillBadge(_ skill: Skill) -> some View {
        HStack(spacing: 2) {
            Text(skill.canonical)
                .font(.caption2)
            if let lastUsed = skill.lastUsed {
                Text("(\(lastUsed))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(artifactProficiencyColor(skill.proficiency).opacity(0.15))
        .foregroundStyle(artifactProficiencyColor(skill.proficiency))
        .cornerRadius(4)
    }
}
