import SwiftUI

/// Displays skills pending approval, grouped by category, with per-skill delete buttons.
/// Distinct from ArtifactSkillsSection: has edit affordance and different visual treatment.
struct ArtifactPendingSkillsSection: View {
    let skills: [Skill]
    let onDeleteSkill: (Skill) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.orange)
                Text("Pending Skills (\(skills.count))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Review before approval")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Skills grouped by category
            let grouped = Dictionary(grouping: skills) { $0.category }
            ForEach(SkillCategoryUtils.sortedCategories(from: skills), id: \.self) { category in
                if let categorySkills = grouped[category], !categorySkills.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)

                        ForEach(categorySkills, id: \.id) { skill in
                            HStack(spacing: 6) {
                                Text(skill.canonical)
                                    .font(.caption)
                                    .lineLimit(1)

                                Spacer()

                                Text(skill.proficiency.rawValue.capitalized)
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(artifactProficiencyColor(skill.proficiency).opacity(0.15))
                                    .foregroundStyle(artifactProficiencyColor(skill.proficiency))
                                    .cornerRadius(3)

                                Button {
                                    onDeleteSkill(skill)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption2)
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                                .help("Remove this skill")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}
