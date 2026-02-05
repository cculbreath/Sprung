//
//  SkillSelectionSheet.swift
//  Sprung
//
//  Selection sheet for adding skills from the skill bank.
//

import SwiftUI

struct SkillSelectionSheet: View {
    /// Values already in the resume (for filtering)
    let existingValues: [String]
    /// Callback when a skill is selected
    let onSelect: (Skill) -> Void

    @Environment(SkillStore.self) private var skillStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var selectedCategory: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add from Skill Bank")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Search and filter
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search skills...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                // Category picker
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(nil as String?)
                    ForEach(SkillCategoryUtils.sortedCategories(from: skillStore.approvedSkills), id: \.self) { category in
                        Text(category).tag(category as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }
            .padding()

            Divider()

            // Skills list
            if filteredSkills.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No skills found")
                        .foregroundStyle(.secondary)
                    if !searchText.isEmpty {
                        Text("Try a different search term")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedSkills.keys.sorted(), id: \.self) { category in
                        Section(header: Text(category)) {
                            ForEach(groupedSkills[category] ?? [], id: \.id) { skill in
                                SkillRow(skill: skill, isAlreadyAdded: isAlreadyAdded(skill))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if !isAlreadyAdded(skill) {
                                            onSelect(skill)
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 400, idealWidth: 500, minHeight: 400, idealHeight: 500)
    }

    // MARK: - Computed Properties

    private var filteredSkills: [Skill] {
        var skills = skillStore.approvedSkills

        // Filter by category
        if let category = selectedCategory {
            skills = skills.filter { $0.category == category }
        }

        // Filter by search
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            skills = skills.filter { skill in
                skill.canonical.lowercased().contains(search) ||
                skill.atsVariants.contains { $0.lowercased().contains(search) }
            }
        }

        return skills.sorted { $0.canonical < $1.canonical }
    }

    private var groupedSkills: [String: [Skill]] {
        Dictionary(grouping: filteredSkills, by: { $0.category })
    }

    private func isAlreadyAdded(_ skill: Skill) -> Bool {
        let lowercasedExisting = Set(existingValues.map { $0.lowercased() })
        return lowercasedExisting.contains(skill.canonical.lowercased()) ||
               skill.atsVariants.contains { lowercasedExisting.contains($0.lowercased()) }
    }
}

// MARK: - Skill Row

private struct SkillRow: View {
    let skill: Skill
    let isAlreadyAdded: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.canonical)
                        .font(.body)
                        .foregroundStyle(isAlreadyAdded ? .secondary : .primary)

                    if !skill.atsVariants.isEmpty {
                        Text("(\(skill.atsVariants.prefix(2).joined(separator: ", "))\(skill.atsVariants.count > 2 ? "..." : ""))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(skill.proficiency.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isAlreadyAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
        .opacity(isAlreadyAdded ? 0.6 : 1.0)
    }
}
