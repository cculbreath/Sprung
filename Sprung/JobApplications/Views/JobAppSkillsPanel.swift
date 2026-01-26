//
//  JobAppSkillsPanel.swift
//  Sprung
//
//  Skills panel showing extracted skills from job description with category styling.
//

import SwiftUI

struct JobAppSkillsPanel: View {
    let skillEvidence: [JobSkillEvidence]
    @Binding var hoveredSkill: JobSkillEvidence?
    @Binding var selectedSkill: JobSkillEvidence?
    @Binding var isEditing: Bool

    private var matchedSkills: [JobSkillEvidence] {
        skillEvidence.filter { $0.category == .matched }
    }

    private var recommendedSkills: [JobSkillEvidence] {
        skillEvidence.filter { $0.category == .recommended }
    }

    private var unmatchedSkills: [JobSkillEvidence] {
        skillEvidence.filter { $0.category == .unmatched }
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
                JobSkillChipView(
                    skill: skill,
                    isActive: isSkillActive(skill),
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
                        } else {
                            selectedSkill = skill
                            hoveredSkill = nil  // Clear hover when clicking
                        }
                    }
                )
            }
        }
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
            legendItem(fillColor: Color(.separatorColor).opacity(0.3), borderColor: Color(.separatorColor), textColor: Color(.labelColor), label: "Unmatched")
            legendItem(fillColor: Color.orange.opacity(0.12), borderColor: Color.orange.opacity(0.4), textColor: Color.orange, label: "Recommended")
            legendItem(fillColor: Color.green.opacity(0.12), borderColor: Color.green.opacity(0.4), textColor: Color.green, label: "Matched")
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
