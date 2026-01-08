import SwiftUI

/// Tab view for browsing experience defaults in the completion review sheet
struct ExperienceDefaultsBrowserTab: View {
    let store: ExperienceDefaultsStore

    @State private var selectedSection: Section = .work

    enum Section: String, CaseIterable {
        case work = "Work"
        case education = "Education"
        case projects = "Projects"
        case skills = "Skills"

        var icon: String {
            switch self {
            case .work: return "briefcase"
            case .education: return "graduationcap"
            case .projects: return "folder"
            case .skills: return "star"
            }
        }
    }

    private var defaults: ExperienceDefaults {
        store.currentDefaults()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section picker
            sectionPicker

            Divider()

            // Section content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedSection {
                    case .work:
                        workSection
                    case .education:
                        educationSection
                    case .projects:
                        projectsSection
                    case .skills:
                        skillsSection
                    }
                }
                .padding(20)
            }
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Section.allCases, id: \.self) { section in
                    sectionButton(section)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func sectionButton(_ section: Section) -> some View {
        let isSelected = selectedSection == section
        let count = countFor(section)

        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.caption)
                Text(section.rawValue)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.green : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func countFor(_ section: Section) -> Int {
        switch section {
        case .work: return defaults.work.count
        case .education: return defaults.education.count
        case .projects: return defaults.projects.count
        case .skills: return defaults.skills.count
        }
    }

    private var workSection: some View {
        Group {
            if defaults.work.isEmpty {
                emptySection(icon: "briefcase", title: "No Work Entries", message: "Work experience will appear here after onboarding")
            } else {
                ForEach(defaults.work) { work in
                    workCard(work)
                }
            }
        }
    }

    private func workCard(_ work: WorkExperienceDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(work.position)
                        .font(.subheadline.weight(.semibold))
                    Text(work.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !work.startDate.isEmpty {
                    Text(formatDateRange(start: work.startDate, end: work.endDate.isEmpty ? nil : work.endDate))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !work.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(work.highlights.prefix(3)) { highlight in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(highlight.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if work.highlights.count > 3 {
                        Text("+\(work.highlights.count - 3) more highlights")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var educationSection: some View {
        Group {
            if defaults.education.isEmpty {
                emptySection(icon: "graduationcap", title: "No Education Entries", message: "Education will appear here after onboarding")
            } else {
                ForEach(defaults.education) { edu in
                    educationCard(edu)
                }
            }
        }
    }

    private func educationCard(_ edu: EducationExperienceDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(edu.institution)
                .font(.subheadline.weight(.semibold))
            HStack {
                if !edu.studyType.isEmpty {
                    Text(edu.studyType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !edu.area.isEmpty {
                    Text("in \(edu.area)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var projectsSection: some View {
        Group {
            if defaults.projects.isEmpty {
                emptySection(icon: "folder", title: "No Projects", message: "Projects will appear here after onboarding")
            } else {
                ForEach(defaults.projects) { project in
                    projectCard(project)
                }
            }
        }
    }

    private func projectCard(_ project: ProjectExperienceDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.name)
                .font(.subheadline.weight(.semibold))

            if !project.description.isEmpty {
                Text(project.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !project.keywords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(project.keywords.prefix(5)) { kw in
                            Text(kw.keyword)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var skillsSection: some View {
        Group {
            if defaults.skills.isEmpty {
                emptySection(icon: "star", title: "No Skills", message: "Skill categories will appear here after onboarding")
            } else {
                ForEach(defaults.skills) { skill in
                    skillCard(skill)
                }
            }
        }
    }

    private func skillCard(_ skill: SkillExperienceDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(skill.name)
                .font(.subheadline.weight(.semibold))

            if !skill.keywords.isEmpty {
                Text(skill.keywords.map { $0.keyword }.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func emptySection(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func formatDateRange(start: String, end: String?) -> String {
        if let end = end {
            return "\(start) – \(end)"
        }
        return "\(start) – Present"
    }
}
