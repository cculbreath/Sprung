import SwiftUI

struct ExperienceEntryHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle, subtitle.isEmpty == false {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WorkExperienceEditor: View {
    @Binding var item: WorkExperienceDraft
    var onChange: () -> Void

    var body: some View {
        ExperienceFieldRow {
            ExperienceTextField("Company", text: $item.name, onChange: onChange)
            ExperienceTextField("Role", text: $item.position, onChange: onChange)
        }
        ExperienceFieldRow {
            ExperienceTextField("Location", text: $item.location, onChange: onChange)
            ExperienceTextField("URL", text: $item.url, onChange: onChange)
        }
        ExperienceFieldRow {
            ExperienceTextField("Start Date", text: $item.startDate, onChange: onChange)
            ExperienceTextField("End Date", text: $item.endDate, onChange: onChange)
        }

        ExperienceTextEditor("Summary", text: $item.summary, onChange: onChange)

        SingleLineHighlightListEditor(items: $item.highlights, onChange: onChange)
    }
}

struct WorkExperienceSummaryView: View {
    let entry: WorkExperienceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryRow(label: "Company", value: entry.name)
            SummaryRow(label: "Location", value: entry.location)
            if let range = dateRangeDescription(entry.startDate, entry.endDate) {
                SummaryRow(label: "Dates", value: range)
            }
            SummaryTextBlock(label: "Summary", value: entry.summary)
            SummaryBulletList(items: entry.highlights.map { $0.text })
        }
        .padding(.top, 4)
    }
}

struct VolunteerExperienceEditor: View {
    @Binding var item: VolunteerExperienceDraft
    var onChange: () -> Void

    var body: some View {
        ExperienceFieldRow {
            ExperienceTextField("Organization", text: $item.organization, onChange: onChange)
            ExperienceTextField("Role", text: $item.position, onChange: onChange)
        }
        ExperienceFieldRow {
            ExperienceTextField("URL", text: $item.url, onChange: onChange)
            ExperienceTextField("Start Date", text: $item.startDate, onChange: onChange)
        }
        ExperienceFieldRow {
            ExperienceTextField("End Date", text: $item.endDate, onChange: onChange)
        }

        ExperienceTextEditor("Summary", text: $item.summary, onChange: onChange)
        VolunteerHighlightListEditor(items: $item.highlights, onChange: onChange)
    }
}

struct VolunteerExperienceSummaryView: View {
    let entry: VolunteerExperienceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryRow(label: "Organization", value: entry.organization)
            if let range = dateRangeDescription(entry.startDate, entry.endDate) {
                SummaryRow(label: "Dates", value: range)
            }
            SummaryTextBlock(label: "Summary", value: entry.summary)
            SummaryBulletList(items: entry.highlights.map { $0.text })
        }
        .padding(.top, 4)
    }
}

struct EducationExperienceEditor: View {
    @Binding var item: EducationExperienceDraft
    var onChange: () -> Void

    var body: some View {
        ExperienceFieldRow {
            ExperienceTextField("Institution", text: $item.institution, onChange: onChange)
            ExperienceTextField("URL", text: $item.url, onChange: onChange)
        }
        ExperienceFieldRow {
            ExperienceTextField("Study Type", text: $item.studyType, onChange: onChange)
            ExperienceTextField("Area of Study", text: $item.area, onChange: onChange)
        }
        ExperienceFieldRow {
            ExperienceTextField("Start Date", text: $item.startDate, onChange: onChange)
            ExperienceTextField("End Date", text: $item.endDate, onChange: onChange)
        }
        ExperienceFieldRow {
            ExperienceTextField("Score / GPA", text: $item.score, onChange: onChange)
        }

        CourseListEditor(items: $item.courses, onChange: onChange)
    }
}

struct EducationExperienceSummaryView: View {
    let entry: EducationExperienceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryRow(label: "Institution", value: entry.institution)
            if let range = dateRangeDescription(entry.startDate, entry.endDate) {
                SummaryRow(label: "Dates", value: range)
            }
            SummaryRow(label: "Study Type", value: entry.studyType)
            SummaryRow(label: "Area", value: entry.area)
            SummaryRow(label: "Score", value: entry.score)
            SummaryBulletList(label: "Courses", items: entry.courses.map { $0.name })
        }
        .padding(.top, 4)
    }
}

struct ProjectExperienceEditor: View {
    @Binding var item: ProjectExperienceDraft
    var onChange: () -> Void

    var body: some View {
        ExperienceFieldRow {
            ExperienceTextField("Name", text: $item.name, onChange: onChange)
            ExperienceTextField("URL", text: $item.url, onChange: onChange)
        }
        ExperienceFieldRow {
            ExperienceTextField("Start Date", text: $item.startDate, onChange: onChange)
            ExperienceTextField("End Date", text: $item.endDate, onChange: onChange)
        }
        ExperienceFieldRow {
            ExperienceTextField("Entity", text: $item.organization, onChange: onChange)
            ExperienceTextField("Type", text: $item.type, onChange: onChange)
        }

        ExperienceTextEditor("Description", text: $item.description, onChange: onChange)

        ProjectHighlightListEditor(items: $item.highlights, onChange: onChange)
        KeywordChipsEditor(title: "Keywords", keywords: $item.keywords, onChange: onChange)
        RoleListEditor(title: "Roles", items: $item.roles, onChange: onChange)
    }
}

struct ProjectExperienceSummaryView: View {
    let entry: ProjectExperienceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let range = dateRangeDescription(entry.startDate, entry.endDate) {
                SummaryRow(label: "Dates", value: range)
            }
            SummaryRow(label: "Entity", value: entry.organization)
            SummaryRow(label: "Type", value: entry.type)
            SummaryTextBlock(label: "Description", value: entry.description)
            SummaryBulletList(items: entry.highlights.map { $0.text })
            SummaryChipGroup(label: "Keywords", values: entry.keywords.map { $0.keyword })
            SummaryChipGroup(label: "Roles", values: entry.roles.map { $0.role })
        }
        .padding(.top, 4)
    }
}

struct SkillExperienceEditor: View {
    @Binding var item: SkillExperienceDraft
    var onChange: () -> Void

    var body: some View {
        ExperienceFieldRow {
            ExperienceTextField("Skill", text: $item.name, onChange: onChange)
            ExperienceTextField("Level", text: $item.level, onChange: onChange)
        }

        KeywordChipsEditor(title: "Keywords", keywords: $item.keywords, onChange: onChange)
    }
}

struct SkillExperienceSummaryView: View {
    let entry: SkillExperienceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryRow(label: "Level", value: entry.level)
            SummaryChipGroup(label: "Keywords", values: entry.keywords.map { $0.keyword })
        }
        .padding(.top, 4)
    }
}

struct AwardExperienceEditor: View {
    @Binding var item: AwardExperienceDraft
    var onChange: () -> Void

    var body: some View {
        ExperienceFieldRow {
            ExperienceTextField("Title", text: $item.title, onChange: onChange)
            ExperienceTextField("Date", text: $item.date, onChange: onChange)
        }
        ExperienceFieldRow {
            ExperienceTextField("Awarder", text: $item.awarder, onChange: onChange)
        }

        ExperienceTextEditor("Summary", text: $item.summary, onChange: onChange)
    }
}

struct AwardExperienceSummaryView: View {
    let entry: AwardExperienceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryRow(label: "Awarder", value: entry.awarder)
            SummaryRow(label: "Date", value: entry.date)
            SummaryTextBlock(label: "Summary", value: entry.summary)
        }
        .padding(.top, 4)
    }
}

struct CertificateExperienceEditor: View {
    @Binding var item: CertificateExperienceDraft
    var onChange: () -> Void

    var body: some View {
        ExperienceFieldRow {
            ExperienceTextField("Name", text: $item.name, onChange: onChange)
            ExperienceTextField("Issuer", text: $item.issuer, onChange: onChange)
        }
        ExperienceFieldRow {
            ExperienceTextField("Date", text: $item.date, onChange: onChange)
            ExperienceTextField("URL", text: $item.url, onChange: onChange)
        }
    }
}

struct CertificateExperienceSummaryView: View {
    let entry: CertificateExperienceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryRow(label: "Issuer", value: entry.issuer)
            SummaryRow(label: "Date", value: entry.date)
            SummaryRow(label: "URL", value: entry.url)
        }
        .padding(.top, 4)
    }
}

struct PublicationExperienceEditor: View {
    @Binding var item: PublicationExperienceDraft
    var onChange: () -> Void

    var body: some View {
        ExperienceFieldRow {
            ExperienceTextField("Title", text: $item.name, onChange: onChange)
            ExperienceTextField("Publisher", text: $item.publisher, onChange: onChange)
        }
        ExperienceFieldRow {
            ExperienceTextField("Release Date", text: $item.releaseDate, onChange: onChange)
            ExperienceTextField("URL", text: $item.url, onChange: onChange)
        }

        ExperienceTextEditor("Summary", text: $item.summary, onChange: onChange)
    }
}

struct PublicationExperienceSummaryView: View {
    let entry: PublicationExperienceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryRow(label: "Publisher", value: entry.publisher)
            SummaryRow(label: "Release Date", value: entry.releaseDate)
            SummaryRow(label: "URL", value: entry.url)
            SummaryTextBlock(label: "Summary", value: entry.summary)
        }
        .padding(.top, 4)
    }
}

struct LanguageExperienceEditor: View {
    @Binding var item: LanguageExperienceDraft
    var onChange: () -> Void

    var body: some View {
        ExperienceFieldRow {
            ExperienceTextField("Language", text: $item.language, onChange: onChange)
            ExperienceTextField("Fluency", text: $item.fluency, onChange: onChange)
        }
    }
}

struct LanguageExperienceSummaryView: View {
    let entry: LanguageExperienceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryRow(label: "Language", value: entry.language)
            SummaryRow(label: "Fluency", value: entry.fluency)
        }
        .padding(.top, 4)
    }
}

struct InterestExperienceEditor: View {
    @Binding var item: InterestExperienceDraft
    var onChange: () -> Void

    var body: some View {
        ExperienceFieldRow {
            ExperienceTextField("Name", text: $item.name, onChange: onChange)
        }
        KeywordChipsEditor(title: "Keywords", keywords: $item.keywords, onChange: onChange)
    }
}

struct InterestExperienceSummaryView: View {
    let entry: InterestExperienceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryRow(label: "Name", value: entry.name)
            SummaryChipGroup(label: "Keywords", values: entry.keywords.map { $0.keyword })
        }
        .padding(.top, 4)
    }
}

struct ReferenceExperienceEditor: View {
    @Binding var item: ReferenceExperienceDraft
    var onChange: () -> Void

    var body: some View {
        ExperienceFieldRow {
            ExperienceTextField("Name", text: $item.name, onChange: onChange)
        }
        ExperienceTextEditor("Reference", text: $item.reference, onChange: onChange)
        ExperienceFieldRow {
            ExperienceTextField("URL", text: $item.url, onChange: onChange)
        }
    }
}

struct ReferenceExperienceSummaryView: View {
    let entry: ReferenceExperienceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryRow(label: "Name", value: entry.name)
            SummaryTextBlock(label: "Reference", value: entry.reference)
            SummaryRow(label: "URL", value: entry.url)
        }
        .padding(.top, 4)
    }
}

private struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        let trimmed = value.trimmed()
        if trimmed.isEmpty == false {
            HStack(alignment: .top, spacing: 6) {
                Text(label.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(trimmed)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct SummaryTextBlock: View {
    let label: String
    let value: String

    var body: some View {
        let trimmed = value.trimmed()
        if trimmed.isEmpty == false {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(trimmed)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct SummaryBulletList: View {
    var label: String?
    let items: [String]

    init(label: String? = nil, items: [String]) {
        self.label = label
        self.items = items
            .map { $0.trimmed() }
            .filter { $0.isEmpty == false }
    }

    var body: some View {
        if items.isEmpty == false {
            VStack(alignment: .leading, spacing: 4) {
                if let label, label.isEmpty == false {
                    Text(label.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items.indices, id: \.self) { index in
                        Text("• \(items[index])")
                    }
                }
            }
        }
    }
}

private struct SummaryChipGroup: View {
    let label: String
    let values: [String]

    var body: some View {
        let chips = values
            .map { $0.trimmed() }
            .filter { $0.isEmpty == false }
        if chips.isEmpty == false {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                WrapLayout(chips: chips)
            }
        }
    }
}

private struct WrapLayout: View {
    let chips: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(chips, id: \.self) { keyword in
                KeywordChip(keyword: keyword)
            }
        }
    }
}
