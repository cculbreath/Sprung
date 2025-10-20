import SwiftUI
import UniformTypeIdentifiers

struct WorkExperienceSectionView: View {
    @Binding var items: [WorkExperienceDraft]
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: "Work Experience", subtitle: "Default roles and accomplishments for new resumes") {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            endEditing(entryID)
                            items.remove(at: index)
                            onChange()
                        }
                    },
                    onToggleEdit: { toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: workTitle(entry),
                        subtitle: workSubtitle(entry)
                    )

                    if editing {
                        WorkExperienceEditor(item: item, onChange: onChange)
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
                        onChange: onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            }

            ExperienceAddButton(title: ExperienceSectionKey.work.addButtonTitle) {
                let entry = WorkExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                beginEditing(entryID)
                onChange()
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
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: "Volunteer Experience") {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            endEditing(entryID)
                            items.remove(at: index)
                            onChange()
                        }
                    },
                    onToggleEdit: { toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: volunteerTitle(entry),
                        subtitle: volunteerSubtitle(entry)
                    )

                    if editing {
                        VolunteerExperienceEditor(item: item, onChange: onChange)
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
                        onChange: onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            }

            ExperienceAddButton(title: ExperienceSectionKey.volunteer.addButtonTitle) {
                let entry = VolunteerExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                beginEditing(entryID)
                onChange()
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
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: "Education", subtitle: "Preconfigured studies, courses, and achievements") {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            endEditing(entryID)
                            items.remove(at: index)
                            onChange()
                        }
                    },
                    onToggleEdit: { toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: educationTitle(entry),
                        subtitle: educationSubtitle(entry)
                    )

                    if editing {
                        EducationExperienceEditor(item: item, onChange: onChange)
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
                        onChange: onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            }

            ExperienceAddButton(title: ExperienceSectionKey.education.addButtonTitle) {
                let entry = EducationExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                beginEditing(entryID)
                onChange()
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
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: "Projects") {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            endEditing(entryID)
                            items.remove(at: index)
                            onChange()
                        }
                    },
                    onToggleEdit: { toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: projectTitle(entry),
                        subtitle: projectSubtitle(entry)
                    )

                    if editing {
                        ProjectExperienceEditor(item: item, onChange: onChange)
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
                        onChange: onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            }

            ExperienceAddButton(title: ExperienceSectionKey.projects.addButtonTitle) {
                let entry = ProjectExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                beginEditing(entryID)
                onChange()
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
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: "Skills") {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            endEditing(entryID)
                            items.remove(at: index)
                            onChange()
                        }
                    },
                    onToggleEdit: { toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: skillTitle(entry),
                        subtitle: skillSubtitle(entry)
                    )

                    if editing {
                        SkillExperienceEditor(item: item, onChange: onChange)
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
                        onChange: onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            }

            ExperienceAddButton(title: ExperienceSectionKey.skills.addButtonTitle) {
                let entry = SkillExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                beginEditing(entryID)
                onChange()
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
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: "Awards") {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            endEditing(entryID)
                            items.remove(at: index)
                            onChange()
                        }
                    },
                    onToggleEdit: { toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: awardTitle(entry),
                        subtitle: awardSubtitle(entry)
                    )

                    if editing {
                        AwardExperienceEditor(item: item, onChange: onChange)
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
                        onChange: onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            }

            ExperienceAddButton(title: ExperienceSectionKey.awards.addButtonTitle) {
                let entry = AwardExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                beginEditing(entryID)
                onChange()
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
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: "Certificates") {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            endEditing(entryID)
                            items.remove(at: index)
                            onChange()
                        }
                    },
                    onToggleEdit: { toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: certificateTitle(entry),
                        subtitle: certificateSubtitle(entry)
                    )

                    if editing {
                        CertificateExperienceEditor(item: item, onChange: onChange)
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
                        onChange: onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            }

            ExperienceAddButton(title: ExperienceSectionKey.certificates.addButtonTitle) {
                let entry = CertificateExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                beginEditing(entryID)
                onChange()
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
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: "Publications") {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            endEditing(entryID)
                            items.remove(at: index)
                            onChange()
                        }
                    },
                    onToggleEdit: { toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: publicationTitle(entry),
                        subtitle: publicationSubtitle(entry)
                    )

                    if editing {
                        PublicationExperienceEditor(item: item, onChange: onChange)
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
                        onChange: onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            }

            ExperienceAddButton(title: ExperienceSectionKey.publications.addButtonTitle) {
                let entry = PublicationExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                beginEditing(entryID)
                onChange()
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
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: "Languages") {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            endEditing(entryID)
                            items.remove(at: index)
                            onChange()
                        }
                    },
                    onToggleEdit: { toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: languageTitle(entry),
                        subtitle: languageSubtitle(entry)
                    )

                    if editing {
                        LanguageExperienceEditor(item: item, onChange: onChange)
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
                        onChange: onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            }

            ExperienceAddButton(title: ExperienceSectionKey.languages.addButtonTitle) {
                let entry = LanguageExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                beginEditing(entryID)
                onChange()
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
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: "Interests") {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            endEditing(entryID)
                            items.remove(at: index)
                            onChange()
                        }
                    },
                    onToggleEdit: { toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: interestTitle(entry),
                        subtitle: nil
                    )

                    if editing {
                        InterestExperienceEditor(item: item, onChange: onChange)
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
                        onChange: onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            }

            ExperienceAddButton(title: ExperienceSectionKey.interests.addButtonTitle) {
                let entry = InterestExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                beginEditing(entryID)
                onChange()
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
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: "References") {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = isEditing(entryID)
                ExperienceCard(
                    onDelete: {
                        if let index = items.firstIndex(where: { $0.id == entryID }) {
                            endEditing(entryID)
                            items.remove(at: index)
                            onChange()
                        }
                    },
                    onToggleEdit: { toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    ExperienceEntryHeader(
                        title: referenceTitle(entry),
                        subtitle: nil
                    )

                    if editing {
                        ReferenceExperienceEditor(item: item, onChange: onChange)
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
                        onChange: onChange
                    )
                )
            }

            if items.isEmpty == false {
                ExperienceSectionTrailingDropArea(
                    items: $items,
                    draggingID: $draggingID,
                    onChange: onChange
                )
            }

            ExperienceAddButton(title: ExperienceSectionKey.references.addButtonTitle) {
                let entry = ReferenceExperienceDraft()
                let entryID = entry.id
                items.append(entry)
                beginEditing(entryID)
                onChange()
            }
        }
    }

    private func referenceTitle(_ entry: ReferenceExperienceDraft) -> String {
        let name = entry.name.trimmed()
        return name.isEmpty ? "Reference" : name
    }
}

// MARK: - Reordering Support

private struct ExperienceReorderDropDelegate<Item: Identifiable & Equatable>: DropDelegate where Item.ID == UUID {
    let target: Item
    @Binding var items: [Item]
    @Binding var draggingID: UUID?
    var onChange: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingID,
              draggingID != target.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggingID }),
              let toIndex = items.firstIndex(of: target) else { return }

        if fromIndex != toIndex {
            withAnimation(.easeInOut(duration: 0.15)) {
                var updated = items
                let element = updated.remove(at: fromIndex)
                let adjustedIndex = fromIndex < toIndex ? toIndex - 1 : toIndex
                let targetIndex = max(min(adjustedIndex, updated.count), 0)
                updated.insert(element, at: targetIndex)
                items = updated
                onChange()
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

private struct ExperienceReorderTrailingDropDelegate<Item: Identifiable & Equatable>: DropDelegate where Item.ID == UUID {
    @Binding var items: [Item]
    @Binding var draggingID: UUID?
    var onChange: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingID,
              let fromIndex = items.firstIndex(where: { $0.id == draggingID }) else { return }
        let lastIndex = max(items.count - 1, 0)
        guard lastIndex >= 0, fromIndex != lastIndex else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            var updated = items
            let element = updated.remove(at: fromIndex)
            updated.append(element)
            items = updated
            onChange()
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
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
