//
//  JobAppSkillsPanel.swift
//  Sprung
//
//  Skills panel showing extracted skills from job description with category styling.
//

import SwiftUI

struct JobAppSkillsPanel: View {
    let skillEvidence: [JobSkillEvidence]
    let skillRecommendations: [SkillRecommendation]
    @Binding var hoveredSkill: JobSkillEvidence?
    @Binding var selectedSkill: JobSkillEvidence?
    @Binding var isEditing: Bool

    @Environment(SkillStore.self) private var skillStore

    // Popover state
    @State private var addSkillTarget: JobSkillEvidence?
    @State private var addSkillProficiency: Proficiency = .familiar
    @State private var addSkillCategory: String = ""
    @State private var addSkillCustomCategory: String = ""
    @State private var recentlyAddedSkills: Set<String> = []

    private var matchedSkills: [JobSkillEvidence] {
        skillEvidence.filter { $0.category == .matched }
    }

    private var recommendedSkills: [JobSkillEvidence] {
        skillEvidence.filter { $0.category == .recommended }
    }

    private var unmatchedSkills: [JobSkillEvidence] {
        skillEvidence.filter { $0.category == .unmatched }
    }

    private var recommendationsByName: [String: SkillRecommendation] {
        Dictionary(uniqueKeysWithValues: skillRecommendations.map { ($0.skillName, $0) })
    }

    private var existingCategories: [String] {
        SkillCategoryUtils.sortedCategories(from: skillStore.skills)
    }

    private var resolvedCategory: String {
        let value = addSkillCategory == "__custom__" ? addSkillCustomCategory : addSkillCategory
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            panelHeader

            Divider()

            // Skills content with legend at the end
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !matchedSkills.isEmpty {
                        skillsSection(skills: matchedSkills)
                    }

                    if !recommendedSkills.isEmpty {
                        skillsSection(skills: recommendedSkills)
                    }

                    if !unmatchedSkills.isEmpty {
                        skillsSection(skills: unmatchedSkills)
                    }

                    if skillEvidence.isEmpty {
                        Text("No skills extracted yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }

                    // Legend at the end of the list
                    if !skillEvidence.isEmpty {
                        legendView
                            .padding(.top, 16)
                    }
                }
                .padding(16)
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.3))
    }

    private var panelHeader: some View {
        HStack {
            Text("Referenced Skills")
                .font(.headline)
            Spacer()
            Button {
                isEditing.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                    Text("Edit")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func skillsSection(skills: [JobSkillEvidence]) -> some View {
        FlowStack(spacing: 8, verticalSpacing: 10) {
            ForEach(skills) { skill in
                let isAddable = skill.category != .matched
                let isAdded = isAddable && isSkillInBank(skill)

                JobSkillChipView(
                    skill: skill,
                    isActive: isSkillActive(skill),
                    isAdded: isAdded,
                    onHover: { hovering in
                        // Only update hover if no skill is selected (click-locked)
                        if selectedSkill == nil {
                            hoveredSkill = hovering ? skill : nil
                        }
                    },
                    onTap: {
                        // Toggle selection on click
                        if selectedSkill?.skillName == skill.skillName {
                            selectedSkill = nil
                            addSkillTarget = nil
                        } else {
                            selectedSkill = skill
                            hoveredSkill = nil
                            // Show add popover for non-matched, non-added skills
                            if isAddable && !isAdded {
                                if let rec = recommendationsByName[skill.skillName] {
                                    // Pre-select existing category or set as custom
                                    if existingCategories.contains(rec.category) {
                                        addSkillCategory = rec.category
                                        addSkillCustomCategory = ""
                                    } else {
                                        addSkillCategory = "__custom__"
                                        addSkillCustomCategory = rec.category
                                    }
                                } else {
                                    addSkillCategory = existingCategories.first ?? "__custom__"
                                    addSkillCustomCategory = ""
                                }
                                addSkillProficiency = .familiar
                                addSkillTarget = skill
                            } else {
                                addSkillTarget = nil
                            }
                        }
                    }
                )
                .popover(
                    isPresented: Binding(
                        get: { addSkillTarget?.skillName == skill.skillName },
                        set: { if !$0 { addSkillTarget = nil } }
                    ),
                    arrowEdge: .bottom
                ) {
                    addToSkillBankPopover(for: skill)
                }
            }
        }
    }

    // MARK: - Add to Skill Bank Popover

    @ViewBuilder
    private func addToSkillBankPopover(for skill: JobSkillEvidence) -> some View {
        let recommendation = recommendationsByName[skill.skillName]
        let alreadyExists = isSkillInBank(skill)

        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("Add to Skill Bank")
                .font(.headline)

            // Skill name + badge
            HStack {
                Text(skill.skillName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if skill.category == .recommended {
                    Text("Recommended")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }

            // Recommendation context (only for recommended skills)
            if let rec = recommendation {
                VStack(alignment: .leading, spacing: 6) {
                    Text(rec.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !rec.relatedUserSkills.isEmpty {
                        HStack(spacing: 4) {
                            Text("Related:")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(rec.relatedUserSkills.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            // Category picker
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Category:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $addSkillCategory) {
                        ForEach(existingCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                        Divider()
                        Text("New Category\u{2026}").tag("__custom__")
                    }
                    .controlSize(.small)
                }

                if addSkillCategory == "__custom__" {
                    TextField("Category name", text: $addSkillCustomCategory)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color(.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // Proficiency picker
            HStack(spacing: 8) {
                Text("Proficiency:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $addSkillProficiency) {
                    Text("Expert").tag(Proficiency.expert)
                    Text("Proficient").tag(Proficiency.proficient)
                    Text("Familiar").tag(Proficiency.familiar)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }

            // Action
            if alreadyExists {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Already in Skill Bank")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Spacer()
                    Button("Add to Skill Bank") {
                        addSkillToBank(skill)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(resolvedCategory.isEmpty)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func addSkillToBank(_ evidence: JobSkillEvidence) {
        guard !resolvedCategory.isEmpty else { return }

        let newSkill = Skill(
            canonical: evidence.skillName,
            category: resolvedCategory,
            proficiency: addSkillProficiency
        )
        skillStore.add(newSkill)
        recentlyAddedSkills.insert(evidence.skillName)
        addSkillTarget = nil
    }

    // MARK: - Helpers

    private func isSkillInBank(_ skill: JobSkillEvidence) -> Bool {
        recentlyAddedSkills.contains(skill.skillName)
            || !skillStore.skills(matching: skill.skillName).isEmpty
    }

    private func isSkillActive(_ skill: JobSkillEvidence) -> Bool {
        // Selected takes priority over hovered
        if let selected = selectedSkill, selected.skillName == skill.skillName {
            return true
        }
        if selectedSkill == nil, let hovered = hoveredSkill, hovered.skillName == skill.skillName {
            return true
        }
        return false
    }

    private var legendView: some View {
        HStack(spacing: 12) {
            legendItem(fillColor: Color.green.opacity(0.12), borderColor: Color.green.opacity(0.4), textColor: Color.green, label: "In Skill Bank")
            legendItem(fillColor: Color.orange.opacity(0.12), borderColor: Color.orange.opacity(0.4), textColor: Color.orange, label: "Likely Have")
            legendItem(fillColor: Color(.separatorColor).opacity(0.3), borderColor: Color(.separatorColor), textColor: Color(.labelColor), label: "Not in Bank")
        }
        .font(.caption)
    }

    private func legendItem(fillColor: Color, borderColor: Color, textColor: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(fillColor)
                .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
                .frame(width: 20, height: 12)
            Text(label)
                .foregroundStyle(textColor)
        }
    }
}
