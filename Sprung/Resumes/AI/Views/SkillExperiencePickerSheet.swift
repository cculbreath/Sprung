//
//  SkillExperiencePickerSheet.swift
//  Sprung
//
//  UI for querying user about their experience level with specific skills.
//  Presented when the LLM calls the query_user_experience_level tool.
//
import SwiftUI

/// Sheet for collecting user's experience levels for a list of skills.
/// Used by the `query_user_experience_level` tool during resume customization.
struct SkillExperiencePickerSheet: View {
    let skills: [SkillQuery]
    let onComplete: ([SkillExperienceResult]) -> Void
    let onCancel: () -> Void

    @State private var selections: [String: ExperienceLevel] = [:]
    @State private var comments: [String: String] = [:]
    @State private var expandedComment: String? = nil

    private var allSkillsSelected: Bool {
        skills.allSatisfy { selections[$0.keyword] != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            skillsListSection
            Divider()
            footerSection
        }
        .frame(width: 650, height: 550)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Initialize all skills to nil (unselected)
            for skill in skills {
                if selections[skill.keyword] == nil {
                    selections[skill.keyword] = nil
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("Rate Your Skill Experience")
                        .font(.title2.weight(.semibold))
                }

                Text("The AI found skills related to your background. Help improve suggestions by rating your experience level.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Skip this step")
        }
        .padding(20)
    }

    // MARK: - Skills List

    private var skillsListSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(skills, id: \.keyword) { skill in
                    SkillExperienceRow(
                        skill: skill,
                        selectedLevel: Binding(
                            get: { selections[skill.keyword] },
                            set: { selections[skill.keyword] = $0 }
                        ),
                        comment: Binding(
                            get: { comments[skill.keyword] ?? "" },
                            set: { comments[skill.keyword] = $0 }
                        ),
                        isExpanded: expandedComment == skill.keyword,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedComment == skill.keyword {
                                    expandedComment = nil
                                } else {
                                    expandedComment = skill.keyword
                                }
                            }
                        }
                    )
                }
            }
            .padding(20)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button("Skip") {
                onCancel()
            }
            .buttonStyle(.bordered)
            .help("Skip without providing experience levels")

            Spacer()

            if !allSkillsSelected {
                Text("\(skills.count - selections.compactMap({ $0.value }).count) skill(s) remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Submit") {
                submitResults()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!allSkillsSelected)
            .help(allSkillsSelected ? "Submit your experience levels" : "Please rate all skills before submitting")
        }
        .padding(20)
    }

    // MARK: - Actions

    private func submitResults() {
        let results: [SkillExperienceResult] = skills.compactMap { skill in
            guard let level = selections[skill.keyword] else { return nil }
            let comment = comments[skill.keyword]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return SkillExperienceResult(
                keyword: skill.keyword,
                level: level,
                comment: comment?.isEmpty == true ? nil : comment
            )
        }
        onComplete(results)
    }
}

// MARK: - Skill Row

private struct SkillExperienceRow: View {
    let skill: SkillQuery
    @Binding var selectedLevel: ExperienceLevel?
    @Binding var comment: String
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Skill name and comment toggle
            HStack {
                Text(skill.keyword)
                    .font(.headline)

                Spacer()

                Button(action: onToggleExpand) {
                    HStack(spacing: 4) {
                        Image(systemName: comment.isEmpty ? "bubble.left" : "bubble.left.fill")
                        if !comment.isEmpty {
                            Text("Comment")
                                .font(.caption)
                        }
                    }
                    .foregroundColor(comment.isEmpty ? .secondary : .blue)
                }
                .buttonStyle(.plain)
                .help("Add a comment about this skill")
            }

            // Experience level picker
            HStack(spacing: 8) {
                ForEach(ExperienceLevel.allCases, id: \.self) { level in
                    ExperienceLevelButton(
                        level: level,
                        isSelected: selectedLevel == level,
                        action: { selectedLevel = level }
                    )
                }
            }

            // Description of selected level
            if let level = selectedLevel {
                Text(level.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            // Comment field (expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Additional context (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $comment)
                        .font(.body)
                        .frame(height: 60)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Experience Level Button

private struct ExperienceLevelButton: View {
    let level: ExperienceLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(level.displayName)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

