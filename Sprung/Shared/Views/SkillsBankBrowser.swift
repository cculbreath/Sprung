import SwiftUI

/// Skills Bank browser showing skills grouped by category in an expandable list view.
struct SkillsBankBrowser: View {
    let skillBank: SkillBank?

    @State private var expandedCategories: Set<SkillCategory> = Set(SkillCategory.allCases)
    @State private var searchText = ""
    @State private var selectedProficiency: Proficiency?

    private var groupedSkills: [SkillCategory: [Skill]] {
        guard let bank = skillBank else { return [:] }

        var skills = bank.skills

        // Apply search filter
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            skills = skills.filter { skill in
                skill.canonical.lowercased().contains(search) ||
                skill.atsVariants.contains { $0.lowercased().contains(search) }
            }
        }

        // Apply proficiency filter
        if let proficiency = selectedProficiency {
            skills = skills.filter { $0.proficiency == proficiency }
        }

        return Dictionary(grouping: skills, by: { $0.category })
    }

    private var sortedCategories: [SkillCategory] {
        SkillCategory.allCases.filter { groupedSkills[$0]?.isEmpty == false }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            if skillBank == nil {
                emptyState
            } else if groupedSkills.isEmpty {
                noMatchesState
            } else {
                // Skills list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedCategories, id: \.self) { category in
                            categorySection(category)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search skills...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Proficiency filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    proficiencyChip(nil, label: "All")
                    ForEach([Proficiency.expert, .proficient, .familiar], id: \.self) { level in
                        proficiencyChip(level, label: level.rawValue.capitalized)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func proficiencyChip(_ proficiency: Proficiency?, label: String) -> some View {
        let isSelected = selectedProficiency == proficiency
        let count: Int
        if let bank = skillBank {
            if let proficiency = proficiency {
                count = bank.skills.filter { $0.proficiency == proficiency }.count
            } else {
                count = bank.skills.count
            }
        } else {
            count = 0
        }

        return Button(action: { selectedProficiency = proficiency }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.orange : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func categorySection(_ category: SkillCategory) -> some View {
        let skills = groupedSkills[category] ?? []
        let isExpanded = expandedCategories.contains(category)

        return VStack(alignment: .leading, spacing: 0) {
            // Category header
            Button(action: { toggleCategory(category) }) {
                HStack {
                    Image(systemName: iconFor(category))
                        .font(.title3)
                        .foregroundStyle(colorFor(category))
                        .frame(width: 24)

                    Text(category.rawValue)
                        .font(.headline)

                    Text("(\(skills.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .buttonStyle(.plain)

            // Skills list (when expanded)
            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(skills.sorted { $0.proficiency.sortOrder < $1.proficiency.sortOrder }) { skill in
                        skillRow(skill)
                    }
                }
                .padding(.leading, 36)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func skillRow(_ skill: Skill) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Proficiency indicator
            Circle()
                .fill(colorFor(skill.proficiency))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                // Skill name
                Text(skill.canonical)
                    .font(.subheadline.weight(.medium))

                // ATS variants (if any)
                if !skill.atsVariants.isEmpty {
                    Text(skill.atsVariants.prefix(3).joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Evidence count
                if !skill.evidence.isEmpty {
                    Label("\(skill.evidence.count) evidence", systemImage: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Last used
            if let lastUsed = skill.lastUsed {
                Text(lastUsed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Proficiency badge
            Text(skill.proficiency.rawValue.capitalized)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(colorFor(skill.proficiency).opacity(0.15))
                .foregroundStyle(colorFor(skill.proficiency))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func toggleCategory(_ category: SkillCategory) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedCategories.contains(category) {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        }
    }

    private func iconFor(_ category: SkillCategory) -> String {
        switch category {
        case .languages: return "chevron.left.forwardslash.chevron.right"
        case .frameworks: return "square.stack.3d.up"
        case .tools: return "wrench.and.screwdriver"
        case .hardware: return "cpu"
        case .fabrication: return "hammer"
        case .scientific: return "flask"
        case .soft: return "person.2"
        case .domain: return "building.2"
        }
    }

    private func colorFor(_ category: SkillCategory) -> Color {
        switch category {
        case .languages: return .blue
        case .frameworks: return .purple
        case .tools: return .orange
        case .hardware: return .red
        case .fabrication: return .brown
        case .scientific: return .green
        case .soft: return .teal
        case .domain: return .indigo
        }
    }

    private func colorFor(_ proficiency: Proficiency) -> Color {
        switch proficiency {
        case .expert: return .green
        case .proficient: return .blue
        case .familiar: return .orange
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Skills Bank")
                .font(.title3.weight(.medium))
            Text("Complete document ingestion to build your skills bank")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No Matching Skills")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Try adjusting your search or filters")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button("Clear Filters") {
                searchText = ""
                selectedProficiency = nil
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
