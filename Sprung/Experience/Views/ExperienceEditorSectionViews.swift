import SwiftUI
import UniformTypeIdentifiers

struct WorkExperienceSectionView: View {
    @Binding var items: [WorkExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    @State private var draggingID: UUID?
    private let metadata = ExperienceSectionKey.work.metadata

    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = callbacks.isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            callbacks.endEditing(entryID)
                            items.remove(at: index)
                            callbacks.onChange()
                        }
                    },
                    onToggleEdit: { callbacks.toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: workTitle(entry),
                        subtitle: workSubtitle(entry)
                    )

                    if editing {
                        WorkExperienceEditor(item: item, onChange: callbacks.onChange)
                    } else {
                        WorkExperienceSummaryView(entry: entry)
                    }
                }
                .onDrag {
                    draggingID = entryID
                    return NSItemProvider(object: entryID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: entry,
                        items: $items,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }

            ExperienceAddButton(title: metadata.addButtonTitle) {
                let entry = WorkExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                callbacks.beginEditing(entryID)
                callbacks.onChange()
            }
        }
    }

    private func workTitle(_ entry: WorkExperienceDraft) -> String {
        if entry.position.trimmed().isEmpty == false { return entry.position.trimmed() }
        if entry.name.trimmed().isEmpty == false { return entry.name.trimmed() }
        return "Work Role"
    }

    private func workSubtitle(_ entry: WorkExperienceDraft) -> String? {
        let company = entry.position.trimmed().isEmpty ? entry.name.trimmed() : nil
        let range = dateRangeDescription(entry.startDate, entry.endDate)
        return summarySubtitle(primary: company, secondary: range)
    }
}

struct VolunteerExperienceSectionView: View {
    @Binding var items: [VolunteerExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    @State private var draggingID: UUID?
    private let metadata = ExperienceSectionKey.volunteer.metadata

    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = callbacks.isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            callbacks.endEditing(entryID)
                            items.remove(at: index)
                            callbacks.onChange()
                        }
                    },
                    onToggleEdit: { callbacks.toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: volunteerTitle(entry),
                        subtitle: volunteerSubtitle(entry)
                    )

                    if editing {
                        VolunteerExperienceEditor(item: item, onChange: callbacks.onChange)
                    } else {
                        VolunteerExperienceSummaryView(entry: entry)
                    }
                }
                .onDrag {
                    draggingID = entryID
                    return NSItemProvider(object: entryID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: entry,
                        items: $items,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }

            ExperienceAddButton(title: metadata.addButtonTitle) {
                let entry = VolunteerExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                callbacks.beginEditing(entryID)
                callbacks.onChange()
            }
        }
    }

    private func volunteerTitle(_ entry: VolunteerExperienceDraft) -> String {
        if entry.position.trimmed().isEmpty == false { return entry.position.trimmed() }
        if entry.organization.trimmed().isEmpty == false { return entry.organization.trimmed() }
        return "Volunteer Role"
    }

    private func volunteerSubtitle(_ entry: VolunteerExperienceDraft) -> String? {
        let organization = entry.position.trimmed().isEmpty ? entry.organization.trimmed() : nil
        let range = dateRangeDescription(entry.startDate, entry.endDate)
        return summarySubtitle(primary: organization, secondary: range)
    }
}

struct EducationExperienceSectionView: View {
    @Binding var items: [EducationExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    @State private var draggingID: UUID?
    private let metadata = ExperienceSectionKey.education.metadata

    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = callbacks.isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            callbacks.endEditing(entryID)
                            items.remove(at: index)
                            callbacks.onChange()
                        }
                    },
                    onToggleEdit: { callbacks.toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: educationTitle(entry),
                        subtitle: educationSubtitle(entry)
                    )

                    if editing {
                        EducationExperienceEditor(item: item, onChange: callbacks.onChange)
                    } else {
                        EducationExperienceSummaryView(entry: entry)
                    }
                }
                .onDrag {
                    draggingID = entryID
                    return NSItemProvider(object: entryID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: entry,
                        items: $items,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }

            ExperienceAddButton(title: metadata.addButtonTitle) {
                let entry = EducationExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                callbacks.beginEditing(entryID)
                callbacks.onChange()
            }
        }
    }

    private func educationTitle(_ entry: EducationExperienceDraft) -> String {
        let study = entry.studyType.trimmed()
        let area = entry.area.trimmed()
        if study.isEmpty == false && area.isEmpty == false {
            return "\(study) in \(area)"
        }
        if study.isEmpty == false { return study }
        if area.isEmpty == false { return area }
        return "Education"
    }

    private func educationSubtitle(_ entry: EducationExperienceDraft) -> String? {
        let institution = entry.institution.trimmed()
        let range = dateRangeDescription(entry.startDate, entry.endDate)
        return summarySubtitle(primary: institution, secondary: range)
    }
}

struct ProjectExperienceSectionView: View {
    @Binding var items: [ProjectExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    @State private var draggingID: UUID?
    private let metadata = ExperienceSectionKey.projects.metadata

    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = callbacks.isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            callbacks.endEditing(entryID)
                            items.remove(at: index)
                            callbacks.onChange()
                        }
                    },
                    onToggleEdit: { callbacks.toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: projectTitle(entry),
                        subtitle: projectSubtitle(entry)
                    )

                    if editing {
                        ProjectExperienceEditor(item: item, onChange: callbacks.onChange)
                    } else {
                        ProjectExperienceSummaryView(entry: entry)
                    }
                }
                .onDrag {
                    draggingID = entryID
                    return NSItemProvider(object: entryID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: entry,
                        items: $items,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }

            ExperienceAddButton(title: metadata.addButtonTitle) {
                let entry = ProjectExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                callbacks.beginEditing(entryID)
                callbacks.onChange()
            }
        }
    }

    private func projectTitle(_ entry: ProjectExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Project" : name
    }

    private func projectSubtitle(_ entry: ProjectExperienceDraft) -> String? {
        let organization = entry.organization.trimmed()
        let range = dateRangeDescription(entry.startDate, entry.endDate)
        return summarySubtitle(primary: organization, secondary: range)
    }
}

struct SkillExperienceSectionView: View {
    @Binding var items: [SkillExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    @State private var draggingID: UUID?
    private let metadata = ExperienceSectionKey.skills.metadata

    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = callbacks.isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            callbacks.endEditing(entryID)
                            items.remove(at: index)
                            callbacks.onChange()
                        }
                    },
                    onToggleEdit: { callbacks.toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: skillTitle(entry),
                        subtitle: skillSubtitle(entry)
                    )

                    if editing {
                        SkillExperienceEditor(item: item, onChange: callbacks.onChange)
                    } else {
                        SkillExperienceSummaryView(entry: entry)
                    }
                }
                .onDrag {
                    draggingID = entryID
                    return NSItemProvider(object: entryID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: entry,
                        items: $items,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }

            ExperienceAddButton(title: metadata.addButtonTitle) {
                let entry = SkillExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                callbacks.beginEditing(entryID)
                callbacks.onChange()
            }
        }
    }

    private func skillTitle(_ entry: SkillExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Skill" : name
    }

    private func skillSubtitle(_ entry: SkillExperienceDraft) -> String? {
        entry.level.trimmed().isEmpty ? nil : entry.level.trimmed()
    }
}

struct AwardExperienceSectionView: View {
    @Binding var items: [AwardExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    @State private var draggingID: UUID?
    private let metadata = ExperienceSectionKey.awards.metadata

    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = callbacks.isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            callbacks.endEditing(entryID)
                            items.remove(at: index)
                            callbacks.onChange()
                        }
                    },
                    onToggleEdit: { callbacks.toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: awardTitle(entry),
                        subtitle: awardSubtitle(entry)
                    )

                    if editing {
                        AwardExperienceEditor(item: item, onChange: callbacks.onChange)
                    } else {
                        AwardExperienceSummaryView(entry: entry)
                    }
                }
                .onDrag {
                    draggingID = entryID
                    return NSItemProvider(object: entryID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: entry,
                        items: $items,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }

            ExperienceAddButton(title: metadata.addButtonTitle) {
                let entry = AwardExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                callbacks.beginEditing(entryID)
                callbacks.onChange()
            }
        }
    }

    private func awardTitle(_ entry: AwardExperienceDraft) -> String {
        let title = entry.title.trimmed()
        return title.isEmpty ? "Award" : title
    }

    private func awardSubtitle(_ entry: AwardExperienceDraft) -> String? {
        summarySubtitle(primary: entry.awarder.trimmed(), secondary: entry.date.trimmed())
    }
}

struct CertificateExperienceSectionView: View {
    @Binding var items: [CertificateExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    @State private var draggingID: UUID?
    private let metadata = ExperienceSectionKey.certificates.metadata

    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = callbacks.isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            callbacks.endEditing(entryID)
                            items.remove(at: index)
                            callbacks.onChange()
                        }
                    },
                    onToggleEdit: { callbacks.toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: certificateTitle(entry),
                        subtitle: certificateSubtitle(entry)
                    )

                    if editing {
                        CertificateExperienceEditor(item: item, onChange: callbacks.onChange)
                    } else {
                        CertificateExperienceSummaryView(entry: entry)
                    }
                }
                .onDrag {
                    draggingID = entryID
                    return NSItemProvider(object: entryID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: entry,
                        items: $items,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }

            ExperienceAddButton(title: metadata.addButtonTitle) {
                let entry = CertificateExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                callbacks.beginEditing(entryID)
                callbacks.onChange()
            }
        }
    }

    private func certificateTitle(_ entry: CertificateExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Certificate" : name
    }

    private func certificateSubtitle(_ entry: CertificateExperienceDraft) -> String? {
        summarySubtitle(primary: entry.issuer.trimmed(), secondary: entry.date.trimmed())
    }
}

struct PublicationExperienceSectionView: View {
    @Binding var items: [PublicationExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    @State private var draggingID: UUID?
    private let metadata = ExperienceSectionKey.publications.metadata

    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = callbacks.isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            callbacks.endEditing(entryID)
                            items.remove(at: index)
                            callbacks.onChange()
                        }
                    },
                    onToggleEdit: { callbacks.toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: publicationTitle(entry),
                        subtitle: publicationSubtitle(entry)
                    )

                    if editing {
                        PublicationExperienceEditor(item: item, onChange: callbacks.onChange)
                    } else {
                        PublicationExperienceSummaryView(entry: entry)
                    }
                }
                .onDrag {
                    draggingID = entryID
                    return NSItemProvider(object: entryID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: entry,
                        items: $items,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }

            ExperienceAddButton(title: metadata.addButtonTitle) {
                let entry = PublicationExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                callbacks.beginEditing(entryID)
                callbacks.onChange()
            }
        }
    }

    private func publicationTitle(_ entry: PublicationExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Publication" : name
    }

    private func publicationSubtitle(_ entry: PublicationExperienceDraft) -> String? {
        summarySubtitle(primary: entry.publisher.trimmed(), secondary: entry.releaseDate.trimmed())
    }
}

struct LanguageExperienceSectionView: View {
    @Binding var items: [LanguageExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    @State private var draggingID: UUID?
    private let metadata = ExperienceSectionKey.languages.metadata

    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = callbacks.isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            callbacks.endEditing(entryID)
                            items.remove(at: index)
                            callbacks.onChange()
                        }
                    },
                    onToggleEdit: { callbacks.toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: languageTitle(entry),
                        subtitle: languageSubtitle(entry)
                    )

                    if editing {
                        LanguageExperienceEditor(item: item, onChange: callbacks.onChange)
                    } else {
                        LanguageExperienceSummaryView(entry: entry)
                    }
                }
                .onDrag {
                    draggingID = entryID
                    return NSItemProvider(object: entryID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: entry,
                        items: $items,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }

            ExperienceAddButton(title: metadata.addButtonTitle) {
                let entry = LanguageExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                callbacks.beginEditing(entryID)
                callbacks.onChange()
            }
        }
    }

    private func languageTitle(_ entry: LanguageExperienceDraft) -> String {
        let language = entry.language.trimmed()
        return language.isEmpty ? "Language" : language
    }

    private func languageSubtitle(_ entry: LanguageExperienceDraft) -> String? {
        entry.fluency.trimmed().isEmpty ? nil : entry.fluency.trimmed()
    }
}

struct InterestExperienceSectionView: View {
    @Binding var items: [InterestExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    @State private var draggingID: UUID?
    private let metadata = ExperienceSectionKey.interests.metadata

    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = callbacks.isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            callbacks.endEditing(entryID)
                            items.remove(at: index)
                            callbacks.onChange()
                        }
                    },
                    onToggleEdit: { callbacks.toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: interestTitle(entry),
                        subtitle: nil
                    )

                    if editing {
                        InterestExperienceEditor(item: item, onChange: callbacks.onChange)
                    } else {
                        InterestExperienceSummaryView(entry: entry)
                    }
                }
                .onDrag {
                    draggingID = entryID
                    return NSItemProvider(object: entryID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: entry,
                        items: $items,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }

            ExperienceAddButton(title: metadata.addButtonTitle) {
                let entry = InterestExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                callbacks.beginEditing(entryID)
                callbacks.onChange()
            }
        }
    }

    private func interestTitle(_ entry: InterestExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Interest" : name
    }
}

struct ReferenceExperienceSectionView: View {
    @Binding var items: [ReferenceExperienceDraft]
    let callbacks: ExperienceSectionViewCallbacks
    @State private var draggingID: UUID?
    private let metadata = ExperienceSectionKey.references.metadata

    var body: some View {
        sectionContainer(title: metadata.title, subtitle: metadata.subtitle) {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = callbacks.isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            callbacks.endEditing(entryID)
                            items.remove(at: index)
                            callbacks.onChange()
                        }
                    },
                    onToggleEdit: { callbacks.toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: referenceTitle(entry),
                        subtitle: nil
                    )

                    if editing {
                        ReferenceExperienceEditor(item: item, onChange: callbacks.onChange)
                    } else {
                        ReferenceExperienceSummaryView(entry: entry)
                    }
                }
                .onDrag {
                    draggingID = entryID
                    return NSItemProvider(object: entryID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ExperienceReorderDropDelegate(
                        target: entry,
                        items: $items,
                        draggingID: $draggingID,
                        onChange: callbacks.onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: callbacks.onChange
                )
            }

            ExperienceAddButton(title: metadata.addButtonTitle) {
                let entry = ReferenceExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                callbacks.beginEditing(entryID)
                callbacks.onChange()
            }
        }
    }

    private func referenceTitle(_ entry: ReferenceExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Reference" : name
    }
}
private struct ExperienceSectionTrailingDropArea<Item: Identifiable & Equatable>: View where Item.ID == UUID {
    @Binding var items: [Item]
    @Binding var draggingID: UUID?
    var onChange: () -> Void

    var body: some View {
        Color.clear
            .frame(height: 10)
            .contentShape(Rectangle())
            .onDrop(
                of: [.plainText],
                delegate: ExperienceReorderTrailingDropDelegate(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            )
    }
}
