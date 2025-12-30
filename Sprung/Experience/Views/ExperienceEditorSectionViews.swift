import SwiftUI
struct WorkExperienceSectionView: View {
    @Binding var items: [WorkExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    var body: some View {
        GenericExperienceSectionView(
            items: $items,
            metadata: ExperienceSectionKey.work.metadata,
            callbacks: callbacks,
            newItem: WorkExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                WorkExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                WorkExperienceSummaryView(entry: entry)
            }
        )
    }
    private static func title(for entry: WorkExperienceDraft) -> String {
        if entry.position.trimmed().isEmpty == false { return entry.position.trimmed() }
        if entry.name.trimmed().isEmpty == false { return entry.name.trimmed() }
        return "Work Role"
    }
    private static func subtitle(for entry: WorkExperienceDraft) -> String? {
        let company = entry.position.trimmed().isEmpty ? entry.name.trimmed() : nil
        let range = dateRangeDescription(entry.startDate, entry.endDate)
        return summarySubtitle(primary: company, secondary: range)
    }
}
struct VolunteerExperienceSectionView: View {
    @Binding var items: [VolunteerExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    var body: some View {
        GenericExperienceSectionView(
            items: $items,
            metadata: ExperienceSectionKey.volunteer.metadata,
            callbacks: callbacks,
            newItem: VolunteerExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                VolunteerExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                VolunteerExperienceSummaryView(entry: entry)
            }
        )
    }
    private static func title(for entry: VolunteerExperienceDraft) -> String {
        if entry.position.trimmed().isEmpty == false { return entry.position.trimmed() }
        if entry.organization.trimmed().isEmpty == false { return entry.organization.trimmed() }
        return "Volunteer Role"
    }
    private static func subtitle(for entry: VolunteerExperienceDraft) -> String? {
        let organization = entry.position.trimmed().isEmpty ? entry.organization.trimmed() : nil
        let range = dateRangeDescription(entry.startDate, entry.endDate)
        return summarySubtitle(primary: organization, secondary: range)
    }
}
struct EducationExperienceSectionView: View {
    @Binding var items: [EducationExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    var body: some View {
        GenericExperienceSectionView(
            items: $items,
            metadata: ExperienceSectionKey.education.metadata,
            callbacks: callbacks,
            newItem: EducationExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                EducationExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                EducationExperienceSummaryView(entry: entry)
            }
        )
    }
    private static func title(for entry: EducationExperienceDraft) -> String {
        let study = entry.studyType.trimmed()
        let area = entry.area.trimmed()
        if study.isEmpty == false && area.isEmpty == false {
            return "\(study) in \(area)"
        }
        if entry.institution.trimmed().isEmpty == false { return entry.institution.trimmed() }
        return "Education"
    }
    private static func subtitle(for entry: EducationExperienceDraft) -> String? {
        let institution = entry.institution.trimmed()
        let range = dateRangeDescription(entry.startDate, entry.endDate)
        return summarySubtitle(primary: institution, secondary: range)
    }
}
struct ProjectExperienceSectionView: View {
    @Binding var items: [ProjectExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    var body: some View {
        GenericExperienceSectionView(
            items: $items,
            metadata: ExperienceSectionKey.projects.metadata,
            callbacks: callbacks,
            newItem: ProjectExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                ProjectExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                ProjectExperienceSummaryView(entry: entry)
            }
        )
    }
    private static func title(for entry: ProjectExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Project" : name
    }
    private static func subtitle(for entry: ProjectExperienceDraft) -> String? {
        let organization = entry.organization.trimmed()
        let range = dateRangeDescription(entry.startDate, entry.endDate)
        return summarySubtitle(primary: organization, secondary: range)
    }
}
struct SkillExperienceSectionView: View {
    @Binding var items: [SkillExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    var body: some View {
        GenericExperienceSectionView(
            items: $items,
            metadata: ExperienceSectionKey.skills.metadata,
            callbacks: callbacks,
            newItem: SkillExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                SkillExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                SkillExperienceSummaryView(entry: entry)
            }
        )
    }
    private static func title(for entry: SkillExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Skill" : name
    }
    private static func subtitle(for entry: SkillExperienceDraft) -> String? {
        let level = entry.level.trimmed()
        return level.isEmpty ? nil : level
    }
}
struct AwardExperienceSectionView: View {
    @Binding var items: [AwardExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    var body: some View {
        GenericExperienceSectionView(
            items: $items,
            metadata: ExperienceSectionKey.awards.metadata,
            callbacks: callbacks,
            newItem: AwardExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                AwardExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                AwardExperienceSummaryView(entry: entry)
            }
        )
    }
    private static func title(for entry: AwardExperienceDraft) -> String {
        let title = entry.title.trimmed()
        return title.isEmpty ? "Award" : title
    }
    private static func subtitle(for entry: AwardExperienceDraft) -> String? {
        summarySubtitle(primary: entry.awarder.trimmed(), secondary: entry.date.trimmed())
    }
}
struct CertificateExperienceSectionView: View {
    @Binding var items: [CertificateExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    var body: some View {
        GenericExperienceSectionView(
            items: $items,
            metadata: ExperienceSectionKey.certificates.metadata,
            callbacks: callbacks,
            newItem: CertificateExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                CertificateExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                CertificateExperienceSummaryView(entry: entry)
            }
        )
    }
    private static func title(for entry: CertificateExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Certificate" : name
    }
    private static func subtitle(for entry: CertificateExperienceDraft) -> String? {
        summarySubtitle(primary: entry.issuer.trimmed(), secondary: entry.date.trimmed())
    }
}
struct PublicationExperienceSectionView: View {
    @Binding var items: [PublicationExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    var body: some View {
        GenericExperienceSectionView(
            items: $items,
            metadata: ExperienceSectionKey.publications.metadata,
            callbacks: callbacks,
            newItem: PublicationExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                PublicationExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                PublicationExperienceSummaryView(entry: entry)
            }
        )
    }
    private static func title(for entry: PublicationExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Publication" : name
    }
    private static func subtitle(for entry: PublicationExperienceDraft) -> String? {
        summarySubtitle(primary: entry.publisher.trimmed(), secondary: entry.releaseDate.trimmed())
    }
}
struct LanguageExperienceSectionView: View {
    @Binding var items: [LanguageExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    var body: some View {
        GenericExperienceSectionView(
            items: $items,
            metadata: ExperienceSectionKey.languages.metadata,
            callbacks: callbacks,
            newItem: LanguageExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                LanguageExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                LanguageExperienceSummaryView(entry: entry)
            }
        )
    }
    private static func title(for entry: LanguageExperienceDraft) -> String {
        let language = entry.language.trimmed()
        return language.isEmpty ? "Language" : language
    }
    private static func subtitle(for entry: LanguageExperienceDraft) -> String? {
        let fluency = entry.fluency.trimmed()
        return fluency.isEmpty ? nil : fluency
    }
}
struct InterestExperienceSectionView: View {
    @Binding var items: [InterestExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    var body: some View {
        GenericExperienceSectionView(
            items: $items,
            metadata: ExperienceSectionKey.interests.metadata,
            callbacks: callbacks,
            newItem: InterestExperienceDraft.init,
            title: Self.title(for:),
            subtitle: { _ in nil },
            editorBuilder: { item, callbacks in
                InterestExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                InterestExperienceSummaryView(entry: entry)
            }
        )
    }
    private static func title(for entry: InterestExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Interest" : name
    }
}
struct ReferenceExperienceSectionView: View {
    @Binding var items: [ReferenceExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    var body: some View {
        GenericExperienceSectionView(
            items: $items,
            metadata: ExperienceSectionKey.references.metadata,
            callbacks: callbacks,
            newItem: ReferenceExperienceDraft.init,
            title: Self.title(for:),
            subtitle: { _ in nil },
            editorBuilder: { item, callbacks in
                ReferenceExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                ReferenceExperienceSummaryView(entry: entry)
            }
        )
    }
    private static func title(for entry: ReferenceExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Reference" : name
    }
}
struct AnyExperienceSectionRenderer: Identifiable {
    let key: ExperienceSectionKey
    private let isEnabledClosure: (ExperienceDefaultsDraft) -> Bool
    private let renderClosure: (Binding<ExperienceDefaultsDraft>, ExperienceSectionViewCallbacks) -> AnyView
    var id: ExperienceSectionKey { key }
    init<Item, Editor: View, Summary: View>(
        key: ExperienceSectionKey,
        metadata: ExperienceSectionMetadata,
        itemsKeyPath: WritableKeyPath<ExperienceDefaultsDraft, [Item]>,
        newItem: @escaping () -> Item,
        title: @escaping (Item) -> String,
        subtitle: @escaping (Item) -> String?,
        editorBuilder: @escaping (Binding<Item>, ExperienceSectionViewCallbacks) -> Editor,
        summaryBuilder: @escaping (Item) -> Summary
    ) where Item: Identifiable & Equatable, Item.ID == UUID {
        self.key = key
        isEnabledClosure = { draft in
            draft[keyPath: metadata.isEnabledKeyPath]
        }
        renderClosure = { draftBinding, callbacks in
            let itemsBinding = Binding(
                get: { draftBinding.wrappedValue[keyPath: itemsKeyPath] },
                set: { newValue in
                    draftBinding.wrappedValue[keyPath: itemsKeyPath] = newValue
                }
            )
            return AnyView(
                GenericExperienceSectionView(
                    items: itemsBinding,
                    metadata: metadata,
                    callbacks: callbacks,
                    newItem: newItem,
                    title: title,
                    subtitle: subtitle,
                    editorBuilder: editorBuilder,
                    summaryBuilder: summaryBuilder
                )
            )
        }
    }
    init(
        key: ExperienceSectionKey,
        isEnabled: @escaping (ExperienceDefaultsDraft) -> Bool,
        render: @escaping (Binding<ExperienceDefaultsDraft>, ExperienceSectionViewCallbacks) -> AnyView
    ) {
        self.key = key
        isEnabledClosure = isEnabled
        renderClosure = render
    }
    func isEnabled(in draft: ExperienceDefaultsDraft) -> Bool {
        isEnabledClosure(draft)
    }
    func render(in draft: Binding<ExperienceDefaultsDraft>, callbacks: ExperienceSectionViewCallbacks) -> AnyView {
        renderClosure(draft, callbacks)
    }
}
enum ExperienceSectionRenderers {
    static let all: [AnyExperienceSectionRenderer] = [
        WorkExperienceSectionView.renderer(),
        VolunteerExperienceSectionView.renderer(),
        EducationExperienceSectionView.renderer(),
        ProjectExperienceSectionView.renderer(),
        SkillExperienceSectionView.renderer(),
        AwardExperienceSectionView.renderer(),
        CertificateExperienceSectionView.renderer(),
        PublicationExperienceSectionView.renderer(),
        LanguageExperienceSectionView.renderer(),
        InterestExperienceSectionView.renderer(),
        ReferenceExperienceSectionView.renderer(),
        CustomExperienceSectionView.renderer()
    ]
}
extension WorkExperienceSectionView {
    static func renderer() -> AnyExperienceSectionRenderer {
        AnyExperienceSectionRenderer(
            key: .work,
            metadata: ExperienceSectionKey.work.metadata,
            itemsKeyPath: \.work,
            newItem: WorkExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                WorkExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                WorkExperienceSummaryView(entry: entry)
            }
        )
    }
}
extension VolunteerExperienceSectionView {
    static func renderer() -> AnyExperienceSectionRenderer {
        AnyExperienceSectionRenderer(
            key: .volunteer,
            metadata: ExperienceSectionKey.volunteer.metadata,
            itemsKeyPath: \.volunteer,
            newItem: VolunteerExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                VolunteerExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                VolunteerExperienceSummaryView(entry: entry)
            }
        )
    }
}
extension EducationExperienceSectionView {
    static func renderer() -> AnyExperienceSectionRenderer {
        AnyExperienceSectionRenderer(
            key: .education,
            metadata: ExperienceSectionKey.education.metadata,
            itemsKeyPath: \.education,
            newItem: EducationExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                EducationExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                EducationExperienceSummaryView(entry: entry)
            }
        )
    }
}
extension ProjectExperienceSectionView {
    static func renderer() -> AnyExperienceSectionRenderer {
        AnyExperienceSectionRenderer(
            key: .projects,
            metadata: ExperienceSectionKey.projects.metadata,
            itemsKeyPath: \.projects,
            newItem: ProjectExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                ProjectExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                ProjectExperienceSummaryView(entry: entry)
            }
        )
    }
}
extension SkillExperienceSectionView {
    static func renderer() -> AnyExperienceSectionRenderer {
        AnyExperienceSectionRenderer(
            key: .skills,
            metadata: ExperienceSectionKey.skills.metadata,
            itemsKeyPath: \.skills,
            newItem: SkillExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                SkillExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                SkillExperienceSummaryView(entry: entry)
            }
        )
    }
}
extension AwardExperienceSectionView {
    static func renderer() -> AnyExperienceSectionRenderer {
        AnyExperienceSectionRenderer(
            key: .awards,
            metadata: ExperienceSectionKey.awards.metadata,
            itemsKeyPath: \.awards,
            newItem: AwardExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                AwardExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                AwardExperienceSummaryView(entry: entry)
            }
        )
    }
}
extension CertificateExperienceSectionView {
    static func renderer() -> AnyExperienceSectionRenderer {
        AnyExperienceSectionRenderer(
            key: .certificates,
            metadata: ExperienceSectionKey.certificates.metadata,
            itemsKeyPath: \.certificates,
            newItem: CertificateExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                CertificateExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                CertificateExperienceSummaryView(entry: entry)
            }
        )
    }
}
extension PublicationExperienceSectionView {
    static func renderer() -> AnyExperienceSectionRenderer {
        AnyExperienceSectionRenderer(
            key: .publications,
            metadata: ExperienceSectionKey.publications.metadata,
            itemsKeyPath: \.publications,
            newItem: PublicationExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                PublicationExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                PublicationExperienceSummaryView(entry: entry)
            }
        )
    }
}
extension LanguageExperienceSectionView {
    static func renderer() -> AnyExperienceSectionRenderer {
        AnyExperienceSectionRenderer(
            key: .languages,
            metadata: ExperienceSectionKey.languages.metadata,
            itemsKeyPath: \.languages,
            newItem: LanguageExperienceDraft.init,
            title: Self.title(for:),
            subtitle: Self.subtitle(for:),
            editorBuilder: { item, callbacks in
                LanguageExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                LanguageExperienceSummaryView(entry: entry)
            }
        )
    }
}
extension InterestExperienceSectionView {
    static func renderer() -> AnyExperienceSectionRenderer {
        AnyExperienceSectionRenderer(
            key: .interests,
            metadata: ExperienceSectionKey.interests.metadata,
            itemsKeyPath: \.interests,
            newItem: InterestExperienceDraft.init,
            title: Self.title(for:),
            subtitle: { _ in nil },
            editorBuilder: { item, callbacks in
                InterestExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                InterestExperienceSummaryView(entry: entry)
            }
        )
    }
}
extension ReferenceExperienceSectionView {
    static func renderer() -> AnyExperienceSectionRenderer {
        AnyExperienceSectionRenderer(
            key: .references,
            metadata: ExperienceSectionKey.references.metadata,
            itemsKeyPath: \.references,
            newItem: ReferenceExperienceDraft.init,
            title: Self.title(for:),
            subtitle: { _ in nil },
            editorBuilder: { item, callbacks in
                ReferenceExperienceEditor(item: item, onChange: callbacks.onChange)
            },
            summaryBuilder: { entry in
                ReferenceExperienceSummaryView(entry: entry)
            }
        )
    }
}
struct CustomExperienceSectionView: View {
    @Binding var fields: [CustomFieldValue]
    @Binding var isEnabled: Bool
    let metadata: ExperienceSectionMetadata
    let callbacks: ExperienceSectionViewCallbacks
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($fields) { $field in
                let fieldID = field.id
                let editing = callbacks.isEditing(fieldID)
                ExperienceCard(
                    onDelete: { delete(fieldID) },
                    onToggleEdit: { callbacks.toggleEditing(fieldID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: field.key.isEmpty ? "New Field" : field.key,
                        subtitle: fieldSummary(field)
                    )
                    if editing {
                        fieldEditor(for: $field)
                    } else {
                        fieldSummaryView(field)
                    }
                }
                .onDrag {
                    draggingID = fieldID
                    return NSItemProvider(object: fieldID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: field,
                        items: $fields,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }
            if !fields.isEmpty {
                ExperienceSectionTrailingDropArea(
                    items: $fields,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }
            ExperienceAddButton(title: "Add Custom Field") {
                addNewField()
            }
        }
    }

    private func fieldSummary(_ field: CustomFieldValue) -> String? {
        let count = field.values.filter { !$0.isEmpty }.count
        return count > 0 ? "\(count) value\(count == 1 ? "" : "s")" : nil
    }

    private func fieldSummaryView(_ field: CustomFieldValue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let nonEmptyValues = field.values.filter { !$0.isEmpty }
            if nonEmptyValues.isEmpty {
                Text("No values")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(nonEmptyValues.prefix(3), id: \.self) { value in
                    Text("• \(value)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if nonEmptyValues.count > 3 {
                    Text("+ \(nonEmptyValues.count - 3) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func fieldEditor(for field: Binding<CustomFieldValue>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Field Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g., jobTitles, tagline, objective", text: field.key)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: field.wrappedValue.key) { _, _ in
                        isEnabled = true
                        callbacks.onChange()
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Values")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(field.values.indices, id: \.self) { valueIndex in
                    HStack {
                        TextField("Value", text: Binding(
                            get: { field.wrappedValue.values[safe: valueIndex] ?? "" },
                            set: { newValue in
                                guard field.wrappedValue.values.indices.contains(valueIndex) else { return }
                                field.wrappedValue.values[valueIndex] = newValue
                                isEnabled = true
                                callbacks.onChange()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Button {
                            guard field.wrappedValue.values.indices.contains(valueIndex) else { return }
                            field.wrappedValue.values.remove(at: valueIndex)
                            if field.wrappedValue.values.isEmpty {
                                field.wrappedValue.values.append("")
                            }
                            callbacks.onChange()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove value")
                    }
                }
                Button {
                    field.wrappedValue.values.append("")
                    isEnabled = true
                    callbacks.onChange()
                } label: {
                    Label("Add Value", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func delete(_ id: UUID) {
        if let index = fields.firstIndex(where: { $0.id == id }) {
            callbacks.endEditing(id)
            fields.remove(at: index)
            if fields.isEmpty { isEnabled = false }
            callbacks.onChange()
        }
    }

    private func addNewField() {
        let field = CustomFieldValue(key: "", values: [""])
        fields.append(field)
        isEnabled = true
        callbacks.beginEditing(field.id)
        callbacks.onChange()
    }
}
extension CustomExperienceSectionView {
    static func renderer() -> AnyExperienceSectionRenderer {
        AnyExperienceSectionRenderer(
            key: .custom,
            isEnabled: { $0.isCustomEnabled },
            render: { draft, callbacks in
                AnyView(
                    CustomExperienceSectionView(
                        fields: draft.customFieldsBinding,
                        isEnabled: draft.customEnabledBinding,
                        metadata: ExperienceSectionKey.custom.metadata,
                        callbacks: callbacks
                    )
                )
            }
        )
    }
}
private extension Binding where Value == ExperienceDefaultsDraft {
    var customFieldsBinding: Binding<[CustomFieldValue]> {
        Binding<[CustomFieldValue]>(
            get: { self.wrappedValue.customFields },
            set: { self.wrappedValue.customFields = $0 }
        )
    }
    var customEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.wrappedValue.isCustomEnabled },
            set: { self.wrappedValue.isCustomEnabled = $0 }
        )
    }
}
private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
