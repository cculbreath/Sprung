import SwiftUI

/// View that displays pending skills for review before approval.
/// Shown in the Interview tab during the card/skill approval step.
struct PendingSkillsCollectionView: View {
    let coordinator: OnboardingInterviewCoordinator

    @State private var expandedCategories: Set<SkillCategory> = Set(SkillCategory.allCases)

    /// Pending skills from SwiftData store (not yet approved)
    private var pendingSkills: [Skill] {
        coordinator.skillStore.pendingSkills
    }

    private var isReadyForApproval: Bool {
        coordinator.ui.cardAssignmentsReadyForApproval
    }

    private var isGenerating: Bool {
        coordinator.ui.isGeneratingCards
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection

            if pendingSkills.isEmpty {
                emptyState
            } else {
                skillsListSection
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Skills")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if !pendingSkills.isEmpty {
                    Text("\(pendingSkills.count) skill\(pendingSkills.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isReadyForApproval && !pendingSkills.isEmpty {
                Text("Review extracted skills, use trash to remove")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.secondary)
            Text("No skills extracted")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var skillsListSection: some View {
        VStack(spacing: 6) {
            let grouped = Dictionary(grouping: pendingSkills, by: { $0.category })
            let sortedCategories = SkillCategory.allCases.filter { grouped[$0] != nil }

            ForEach(sortedCategories, id: \.self) { category in
                if let categorySkills = grouped[category] {
                    categorySection(category: category, skills: categorySkills)
                }
            }
        }
    }

    @ViewBuilder
    private func categorySection(category: SkillCategory, skills: [Skill]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    Text(category.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text("(\(skills.count))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedCategories.contains(category) {
                ForEach(skills.sorted { $0.proficiency.sortOrder < $1.proficiency.sortOrder }) { skill in
                    PendingSkillRow(
                        skill: skill,
                        showDeleteButton: isReadyForApproval && !isGenerating,
                        onDelete: {
                            coordinator.skillStore.delete(skill)
                        }
                    )
                }
            }
        }
    }
}

private struct PendingSkillRow: View {
    let skill: Skill
    let showDeleteButton: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Skill name
            Text(skill.canonical)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            // Evidence count
            if !skill.evidence.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                    Text("\(skill.evidence.count)")
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(.tertiary)
            }

            // Proficiency badge
            Text(skill.proficiency.rawValue.capitalized)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(proficiencyColor.opacity(0.15))
                )
                .foregroundStyle(proficiencyColor)

            // Delete button
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
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(5)
    }

    private var proficiencyColor: Color {
        switch skill.proficiency {
        case .expert: return .green
        case .proficient: return .blue
        case .familiar: return .orange
        }
    }
}
