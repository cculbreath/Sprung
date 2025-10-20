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

    private static let fieldLayout: [ExperienceFieldLayout<WorkExperienceDraft>] = [
        .row([.textField("Company", \.name), .textField("Role", \.position)]),
        .row([.textField("Location", \.location), .textField("URL", \.url)]),
        .row([.textField("Start Date", \.startDate), .textField("End Date", \.endDate)]),
        .block(.textEditor("Summary", \.summary))
    ]

    var body: some View {
        ExperienceFieldFactory(
            layout: Self.fieldLayout,
            model: $item,
            onChange: onChange
        )
        SingleLineHighlightListEditor(items: $item.highlights, onChange: onChange)
    }
}

struct WorkExperienceSummaryView: View {
    let entry: WorkExperienceDraft

    private static let descriptors: [SummaryFieldDescriptor<WorkExperienceDraft>] = [
        .row(label: "Company", keyPath: \.name),
        .row(label: "Location", keyPath: \.location),
        .optionalRow(label: "Dates") { dateRangeDescription($0.startDate, $0.endDate) },
        .textBlock(label: "Summary", keyPath: \.summary),
        .bulletList { $0.highlights.map(\.text) }
    ]

    var body: some View {
        SummarySectionFactory(entry: entry, descriptors: Self.descriptors)
    }
}

struct VolunteerExperienceEditor: View {
    @Binding var item: VolunteerExperienceDraft
    var onChange: () -> Void

    private static let fieldLayout: [ExperienceFieldLayout<VolunteerExperienceDraft>] = [
        .row([.textField("Organization", \.organization), .textField("Role", \.position)]),
        .row([.textField("URL", \.url), .textField("Start Date", \.startDate)]),
        .row([.textField("End Date", \.endDate)]),
        .block(.textEditor("Summary", \.summary))
    ]

    var body: some View {
        ExperienceFieldFactory(
            layout: Self.fieldLayout,
            model: $item,
            onChange: onChange
        )
        VolunteerHighlightListEditor(items: $item.highlights, onChange: onChange)
    }
}

struct VolunteerExperienceSummaryView: View {
    let entry: VolunteerExperienceDraft

    private static let descriptors: [SummaryFieldDescriptor<VolunteerExperienceDraft>] = [
        .row(label: "Organization", keyPath: \.organization),
        .optionalRow(label: "Dates") { dateRangeDescription($0.startDate, $0.endDate) },
        .textBlock(label: "Summary", keyPath: \.summary),
        .bulletList { $0.highlights.map(\.text) }
    ]

    var body: some View {
        SummarySectionFactory(entry: entry, descriptors: Self.descriptors)
    }
}

struct EducationExperienceEditor: View {
    @Binding var item: EducationExperienceDraft
    var onChange: () -> Void

    private static let fieldLayout: [ExperienceFieldLayout<EducationExperienceDraft>] = [
        .row([.textField("Institution", \.institution), .textField("URL", \.url)]),
        .row([.textField("Study Type", \.studyType), .textField("Area of Study", \.area)]),
        .row([.textField("Start Date", \.startDate), .textField("End Date", \.endDate)]),
        .row([.textField("Score / GPA", \.score)])
    ]

    var body: some View {
        ExperienceFieldFactory(
            layout: Self.fieldLayout,
            model: $item,
            onChange: onChange
        )
        CourseListEditor(items: $item.courses, onChange: onChange)
    }
}

struct EducationExperienceSummaryView: View {
    let entry: EducationExperienceDraft

    private static let descriptors: [SummaryFieldDescriptor<EducationExperienceDraft>] = [
        .row(label: "Institution", keyPath: \.institution),
        .optionalRow(label: "Dates") { dateRangeDescription($0.startDate, $0.endDate) },
        .row(label: "Study Type", keyPath: \.studyType),
        .row(label: "Area", keyPath: \.area),
        .row(label: "Score", keyPath: \.score),
        .bulletList(label: "Courses") { $0.courses.map(\.name) }
    ]

    var body: some View {
        SummarySectionFactory(entry: entry, descriptors: Self.descriptors)
    }
}

struct ProjectExperienceEditor: View {
    @Binding var item: ProjectExperienceDraft
    var onChange: () -> Void

    private static let fieldLayout: [ExperienceFieldLayout<ProjectExperienceDraft>] = [
        .row([.textField("Name", \.name), .textField("URL", \.url)]),
        .row([.textField("Start Date", \.startDate), .textField("End Date", \.endDate)]),
        .row([.textField("Entity", \.organization), .textField("Type", \.type)]),
        .block(.textEditor("Description", \.description))
    ]

    var body: some View {
        ExperienceFieldFactory(
            layout: Self.fieldLayout,
            model: $item,
            onChange: onChange
        )
        ProjectHighlightListEditor(items: $item.highlights, onChange: onChange)
        KeywordChipsEditor(title: "Keywords", keywords: $item.keywords, onChange: onChange)
        RoleListEditor(title: "Roles", items: $item.roles, onChange: onChange)
    }
}

struct ProjectExperienceSummaryView: View {
    let entry: ProjectExperienceDraft

    private static let descriptors: [SummaryFieldDescriptor<ProjectExperienceDraft>] = [
        .optionalRow(label: "Dates") { dateRangeDescription($0.startDate, $0.endDate) },
        .row(label: "Entity", keyPath: \.organization),
        .row(label: "Type", keyPath: \.type),
        .textBlock(label: "Description", keyPath: \.description),
        .bulletList { $0.highlights.map(\.text) },
        .chipGroup(label: "Keywords") { $0.keywords.map(\.keyword) },
        .chipGroup(label: "Roles") { $0.roles.map(\.role) }
    ]

    var body: some View {
        SummarySectionFactory(entry: entry, descriptors: Self.descriptors)
    }
}

struct SkillExperienceEditor: View {
    @Binding var item: SkillExperienceDraft
    var onChange: () -> Void

    private static let fieldLayout: [ExperienceFieldLayout<SkillExperienceDraft>] = [
        .row([.textField("Skill", \.name), .textField("Level", \.level)])
    ]

    var body: some View {
        ExperienceFieldFactory(
            layout: Self.fieldLayout,
            model: $item,
            onChange: onChange
        )
        KeywordChipsEditor(title: "Keywords", keywords: $item.keywords, onChange: onChange)
    }
}

struct SkillExperienceSummaryView: View {
    let entry: SkillExperienceDraft

    private static let descriptors: [SummaryFieldDescriptor<SkillExperienceDraft>] = [
        .row(label: "Level", keyPath: \.level),
        .chipGroup(label: "Keywords") { $0.keywords.map(\.keyword) }
    ]

    var body: some View {
        SummarySectionFactory(entry: entry, descriptors: Self.descriptors)
    }
}

struct AwardExperienceEditor: View {
    @Binding var item: AwardExperienceDraft
    var onChange: () -> Void

    private static let fieldLayout: [ExperienceFieldLayout<AwardExperienceDraft>] = [
        .row([.textField("Title", \.title), .textField("Date", \.date)]),
        .row([.textField("Awarder", \.awarder)]),
        .block(.textEditor("Summary", \.summary))
    ]

    var body: some View {
        ExperienceFieldFactory(
            layout: Self.fieldLayout,
            model: $item,
            onChange: onChange
        )
    }
}

struct AwardExperienceSummaryView: View {
    let entry: AwardExperienceDraft

    private static let descriptors: [SummaryFieldDescriptor<AwardExperienceDraft>] = [
        .row(label: "Awarder", keyPath: \.awarder),
        .row(label: "Date", keyPath: \.date),
        .textBlock(label: "Summary", keyPath: \.summary)
    ]

    var body: some View {
        SummarySectionFactory(entry: entry, descriptors: Self.descriptors)
    }
}

struct CertificateExperienceEditor: View {
    @Binding var item: CertificateExperienceDraft
    var onChange: () -> Void

    private static let fieldLayout: [ExperienceFieldLayout<CertificateExperienceDraft>] = [
        .row([.textField("Name", \.name), .textField("Issuer", \.issuer)]),
        .row([.textField("Date", \.date), .textField("URL", \.url)])
    ]

    var body: some View {
        ExperienceFieldFactory(
            layout: Self.fieldLayout,
            model: $item,
            onChange: onChange
        )
    }
}

struct CertificateExperienceSummaryView: View {
    let entry: CertificateExperienceDraft

    private static let descriptors: [SummaryFieldDescriptor<CertificateExperienceDraft>] = [
        .row(label: "Issuer", keyPath: \.issuer),
        .row(label: "Date", keyPath: \.date),
        .row(label: "URL", keyPath: \.url)
    ]

    var body: some View {
        SummarySectionFactory(entry: entry, descriptors: Self.descriptors)
    }
}

struct PublicationExperienceEditor: View {
    @Binding var item: PublicationExperienceDraft
    var onChange: () -> Void

    private static let fieldLayout: [ExperienceFieldLayout<PublicationExperienceDraft>] = [
        .row([.textField("Title", \.name), .textField("Publisher", \.publisher)]),
        .row([.textField("Release Date", \.releaseDate), .textField("URL", \.url)]),
        .block(.textEditor("Summary", \.summary))
    ]

    var body: some View {
        ExperienceFieldFactory(
            layout: Self.fieldLayout,
            model: $item,
            onChange: onChange
        )
    }
}

struct PublicationExperienceSummaryView: View {
    let entry: PublicationExperienceDraft

    private static let descriptors: [SummaryFieldDescriptor<PublicationExperienceDraft>] = [
        .row(label: "Publisher", keyPath: \.publisher),
        .row(label: "Release Date", keyPath: \.releaseDate),
        .row(label: "URL", keyPath: \.url),
        .textBlock(label: "Summary", keyPath: \.summary)
    ]

    var body: some View {
        SummarySectionFactory(entry: entry, descriptors: Self.descriptors)
    }
}

struct LanguageExperienceEditor: View {
    @Binding var item: LanguageExperienceDraft
    var onChange: () -> Void

    private static let fieldLayout: [ExperienceFieldLayout<LanguageExperienceDraft>] = [
        .row([.textField("Language", \.language), .textField("Fluency", \.fluency)])
    ]

    var body: some View {
        ExperienceFieldFactory(
            layout: Self.fieldLayout,
            model: $item,
            onChange: onChange
        )
    }
}

struct LanguageExperienceSummaryView: View {
    let entry: LanguageExperienceDraft

    private static let descriptors: [SummaryFieldDescriptor<LanguageExperienceDraft>] = [
        .row(label: "Language", keyPath: \.language),
        .row(label: "Fluency", keyPath: \.fluency)
    ]

    var body: some View {
        SummarySectionFactory(entry: entry, descriptors: Self.descriptors)
    }
}

struct InterestExperienceEditor: View {
    @Binding var item: InterestExperienceDraft
    var onChange: () -> Void

    private static let fieldLayout: [ExperienceFieldLayout<InterestExperienceDraft>] = [
        .row([.textField("Name", \.name)])
    ]

    var body: some View {
        ExperienceFieldFactory(
            layout: Self.fieldLayout,
            model: $item,
            onChange: onChange
        )
        KeywordChipsEditor(title: "Keywords", keywords: $item.keywords, onChange: onChange)
    }
}

struct InterestExperienceSummaryView: View {
    let entry: InterestExperienceDraft

    private static let descriptors: [SummaryFieldDescriptor<InterestExperienceDraft>] = [
        .row(label: "Name", keyPath: \.name),
        .chipGroup(label: "Keywords") { $0.keywords.map(\.keyword) }
    ]

    var body: some View {
        SummarySectionFactory(entry: entry, descriptors: Self.descriptors)
    }
}

struct ReferenceExperienceEditor: View {
    @Binding var item: ReferenceExperienceDraft
    var onChange: () -> Void

    private static let fieldLayout: [ExperienceFieldLayout<ReferenceExperienceDraft>] = [
        .row([.textField("Name", \.name)]),
        .block(.textEditor("Reference", \.reference)),
        .row([.textField("URL", \.url)])
    ]

    var body: some View {
        ExperienceFieldFactory(
            layout: Self.fieldLayout,
            model: $item,
            onChange: onChange
        )
    }
}

struct ReferenceExperienceSummaryView: View {
    let entry: ReferenceExperienceDraft

    private static let descriptors: [SummaryFieldDescriptor<ReferenceExperienceDraft>] = [
        .row(label: "Name", keyPath: \.name),
        .textBlock(label: "Reference", keyPath: \.reference),
        .row(label: "URL", keyPath: \.url)
    ]

    var body: some View {
        SummarySectionFactory(entry: entry, descriptors: Self.descriptors)
    }
}

struct SummaryRow: View {
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

struct SummaryTextBlock: View {
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

struct SummaryBulletList: View {
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

struct SummaryChipGroup: View {
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
