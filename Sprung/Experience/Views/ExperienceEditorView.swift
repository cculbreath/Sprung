import SwiftUI

struct ExperienceEditorView: View {
    @Environment(ExperienceDefaultsStore.self) private var defaultsStore: ExperienceDefaultsStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ExperienceDefaultsDraft()
    @State private var originalDraft = ExperienceDefaultsDraft()
    @State private var isLoading = true
    @State private var showSectionBrowser = false
    @State private var hasChanges = false
    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 1080, minHeight: 780)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await loadDraft()
        }
        .onChange(of: draft) { oldValue, newValue in
            hasChanges = newValue != originalDraft
            if saveState == .saved {
                saveState = .idle
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    showSectionBrowser.toggle()
                }
            } label: {
                Label(showSectionBrowser ? "Hide Sections" : "Enable Sections", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)

            if case .saved = saveState {
                Text("✅ Changes saved")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if case .error(let message) = saveState {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()

            Button("Cancel") {
                cancelAndClose()
            }
            .disabled(isLoading || hasChanges == false)

            Button("Save") {
                Task {
                    let didSave = await saveDraft()
                    if didSave {
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || hasChanges == false || saveState == .saving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    private var content: some View {
        HStack(spacing: 0) {
            if showSectionBrowser {
                ExperienceSectionBrowserView(draft: $draft)
                    .frame(width: 280)
                    .background(Color(NSColor.controlBackgroundColor))
                    .transition(.move(edge: .leading))
                    .padding(.trailing, 1)
            }

            Divider()

            if isLoading {
                ProgressView("Loading experience defaults…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if draft.isWorkEnabled {
                            WorkExperienceSectionView(items: $draft.work, onChange: markDirty)
                        }

                        if draft.isVolunteerEnabled {
                            VolunteerExperienceSectionView(items: $draft.volunteer, onChange: markDirty)
                        }

                        if draft.isEducationEnabled {
                            EducationExperienceSectionView(items: $draft.education, onChange: markDirty)
                        }

                        if draft.isProjectsEnabled {
                            ProjectExperienceSectionView(items: $draft.projects, onChange: markDirty)
                        }

                        if draft.isSkillsEnabled {
                            SkillExperienceSectionView(items: $draft.skills, onChange: markDirty)
                        }

                        if draft.isAwardsEnabled {
                            AwardExperienceSectionView(items: $draft.awards, onChange: markDirty)
                        }

                        if draft.isCertificatesEnabled {
                            CertificateExperienceSectionView(items: $draft.certificates, onChange: markDirty)
                        }

                        if draft.isPublicationsEnabled {
                            PublicationExperienceSectionView(items: $draft.publications, onChange: markDirty)
                        }

                        if draft.isLanguagesEnabled {
                            LanguageExperienceSectionView(items: $draft.languages, onChange: markDirty)
                        }

                        if draft.isInterestsEnabled {
                            InterestExperienceSectionView(items: $draft.interests, onChange: markDirty)
                        }

                        if draft.isReferencesEnabled {
                            ReferenceExperienceSectionView(items: $draft.references, onChange: markDirty)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showSectionBrowser)
    }

    // MARK: - Actions

    private func markDirty() {
        hasChanges = true
        if saveState == .saved {
            saveState = .idle
        }
    }

    @MainActor
    private func loadDraft() async {
        let loadedDraft = defaultsStore.loadDraft()
        draft = loadedDraft
        originalDraft = loadedDraft
        hasChanges = false
        isLoading = false
    }

    @MainActor
    private func saveDraft() async -> Bool {
        guard hasChanges else { return true }
        saveState = .saving
        defaultsStore.save(draft: draft)
        originalDraft = draft
        hasChanges = false
        saveState = .saved
        return true
    }

    private func cancelAndClose() {
        draft = originalDraft
        hasChanges = false
        saveState = .idle
        dismiss()
    }
}

// MARK: - Section Browser

private struct ExperienceSectionBrowserView: View {
    @Binding var draft: ExperienceDefaultsDraft
    @State private var expandedSections: Set<ExperienceSectionKey> = Set(ExperienceSectionKey.allCases)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sections")
                    .font(.headline)
                    .padding(.top, 12)

                ForEach(ExperienceSchema.sections) { section in
                    DisclosureGroup(isExpanded: binding(for: section.key)) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(section.nodes) { node in
                                nodeView(node, indentLevel: 1)
                            }
                        }
                        .padding(.leading, 4)
                        .padding(.bottom, 4)
                    } label: {
                        HStack {
                            Text(section.title)
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: sectionToggle(for: section.key))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                        }
                        .padding(.vertical, 4)
                    }
                    .disclosureGroupStyle(.automatic)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func nodeView(_ node: ExperienceSchemaNode, indentLevel: Int) -> some View {
        switch node.kind {
        case .field(let name):
            return AnyView(
                HStack(spacing: 6) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, CGFloat(indentLevel) * 12)
            )
        case .group(let name, let children):
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("▸")
                            .foregroundStyle(.secondary)
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, CGFloat(indentLevel) * 12)

                    ForEach(children) { child in
                        nodeView(child, indentLevel: indentLevel + 1)
                    }
                }
            )
        }
    }

    private func binding(for key: ExperienceSectionKey) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(key)
                } else {
                    expandedSections.remove(key)
                }
            }
        )
    }

    private func sectionToggle(for key: ExperienceSectionKey) -> Binding<Bool> {
        switch key {
        case .work:
            return $draft.isWorkEnabled
        case .volunteer:
            return $draft.isVolunteerEnabled
        case .education:
            return $draft.isEducationEnabled
        case .projects:
            return $draft.isProjectsEnabled
        case .skills:
            return $draft.isSkillsEnabled
        case .awards:
            return $draft.isAwardsEnabled
        case .certificates:
            return $draft.isCertificatesEnabled
        case .publications:
            return $draft.isPublicationsEnabled
        case .languages:
            return $draft.isLanguagesEnabled
        case .interests:
            return $draft.isInterestsEnabled
        case .references:
            return $draft.isReferencesEnabled
        }
    }
}

// MARK: - Generic editor helpers

private struct ExperienceCard<Content: View>: View {
    let onDelete: () -> Void
    let content: Content
    @State private var isHovered = false

    init(onDelete: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHovered ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isHovered ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(8)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct ExperienceSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExperienceAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }
}

// MARK: - Section Views

private struct WorkExperienceSectionView: View {
    @Binding var items: [WorkExperienceDraft]
    var onChange: () -> Void

    var body: some View {
        sectionContainer(title: "Work Experience", subtitle: "Default roles and accomplishments for new resumes") {
            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
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

                    HighlightListEditor(title: "Highlights", items: $item.highlights, onChange: onChange)
                }
            }

            ExperienceAddButton(title: ExperienceSectionKey.work.addButtonTitle) {
                items.append(WorkExperienceDraft())
                onChange()
            }
        }
    }
}

private struct VolunteerExperienceSectionView: View {
    @Binding var items: [VolunteerExperienceDraft]
    var onChange: () -> Void

    var body: some View {
        sectionContainer(title: "Volunteer Experience") {
            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
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

            ExperienceAddButton(title: ExperienceSectionKey.volunteer.addButtonTitle) {
                items.append(VolunteerExperienceDraft())
                onChange()
            }
        }
    }
}

private struct EducationExperienceSectionView: View {
    @Binding var items: [EducationExperienceDraft]
    var onChange: () -> Void

    var body: some View {
        sectionContainer(title: "Education", subtitle: "Preconfigured studies, courses, and achievements") {
            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
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

            ExperienceAddButton(title: ExperienceSectionKey.education.addButtonTitle) {
                items.append(EducationExperienceDraft())
                onChange()
            }
        }
    }
}

private struct ProjectExperienceSectionView: View {
    @Binding var items: [ProjectExperienceDraft]
    var onChange: () -> Void

    var body: some View {
        sectionContainer(title: "Projects") {
            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
                    ExperienceFieldRow {
                        ExperienceTextField("Name", text: $item.name, onChange: onChange)
                        ExperienceTextField("URL", text: $item.url, onChange: onChange)
                    }
                    ExperienceFieldRow {
                        ExperienceTextField("Start Date", text: $item.startDate, onChange: onChange)
                        ExperienceTextField("End Date", text: $item.endDate, onChange: onChange)
                    }
                    ExperienceFieldRow {
                        ExperienceTextField("Entity", text: $item.entity, onChange: onChange)
                        ExperienceTextField("Type", text: $item.type, onChange: onChange)
                    }

                    ExperienceTextEditor("Description", text: $item.description, onChange: onChange)

                    ProjectHighlightListEditor(items: $item.highlights, onChange: onChange)
                    KeywordListEditor(title: "Keywords", items: $item.keywords, onChange: onChange)
                    RoleListEditor(title: "Roles", items: $item.roles, onChange: onChange)
                }
            }

            ExperienceAddButton(title: ExperienceSectionKey.projects.addButtonTitle) {
                items.append(ProjectExperienceDraft())
                onChange()
            }
        }
    }
}

private struct SkillExperienceSectionView: View {
    @Binding var items: [SkillExperienceDraft]
    var onChange: () -> Void

    var body: some View {
        sectionContainer(title: "Skills") {
            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
                    ExperienceFieldRow {
                        ExperienceTextField("Skill", text: $item.name, onChange: onChange)
                        ExperienceTextField("Level", text: $item.level, onChange: onChange)
                    }

                    KeywordListEditor(title: "Keywords", items: $item.keywords, onChange: onChange)
                }
            }

            ExperienceAddButton(title: ExperienceSectionKey.skills.addButtonTitle) {
                items.append(SkillExperienceDraft())
                onChange()
            }
        }
    }
}

private struct AwardExperienceSectionView: View {
    @Binding var items: [AwardExperienceDraft]
    var onChange: () -> Void

    var body: some View {
        sectionContainer(title: "Awards") {
            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
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

            ExperienceAddButton(title: ExperienceSectionKey.awards.addButtonTitle) {
                items.append(AwardExperienceDraft())
                onChange()
            }
        }
    }
}

private struct CertificateExperienceSectionView: View {
    @Binding var items: [CertificateExperienceDraft]
    var onChange: () -> Void

    var body: some View {
        sectionContainer(title: "Certificates") {
            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
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

            ExperienceAddButton(title: ExperienceSectionKey.certificates.addButtonTitle) {
                items.append(CertificateExperienceDraft())
                onChange()
            }
        }
    }
}

private struct PublicationExperienceSectionView: View {
    @Binding var items: [PublicationExperienceDraft]
    var onChange: () -> Void

    var body: some View {
        sectionContainer(title: "Publications") {
            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
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

            ExperienceAddButton(title: ExperienceSectionKey.publications.addButtonTitle) {
                items.append(PublicationExperienceDraft())
                onChange()
            }
        }
    }
}

private struct LanguageExperienceSectionView: View {
    @Binding var items: [LanguageExperienceDraft]
    var onChange: () -> Void

    var body: some View {
        sectionContainer(title: "Languages") {
            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
                    ExperienceFieldRow {
                        ExperienceTextField("Language", text: $item.language, onChange: onChange)
                        ExperienceTextField("Fluency", text: $item.fluency, onChange: onChange)
                    }
                }
            }

            ExperienceAddButton(title: ExperienceSectionKey.languages.addButtonTitle) {
                items.append(LanguageExperienceDraft())
                onChange()
            }
        }
    }
}

private struct InterestExperienceSectionView: View {
    @Binding var items: [InterestExperienceDraft]
    var onChange: () -> Void

    var body: some View {
        sectionContainer(title: "Interests") {
            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
                    ExperienceFieldRow {
                        ExperienceTextField("Name", text: $item.name, onChange: onChange)
                    }
                    KeywordListEditor(title: "Keywords", items: $item.keywords, onChange: onChange)
                }
            }

            ExperienceAddButton(title: ExperienceSectionKey.interests.addButtonTitle) {
                items.append(InterestExperienceDraft())
                onChange()
            }
        }
    }
}

private struct ReferenceExperienceSectionView: View {
    @Binding var items: [ReferenceExperienceDraft]
    var onChange: () -> Void

    var body: some View {
        sectionContainer(title: "References") {
            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
                    ExperienceFieldRow {
                        ExperienceTextField("Name", text: $item.name, onChange: onChange)
                    }
                    ExperienceTextEditor("Reference", text: $item.reference, onChange: onChange)
                    ExperienceFieldRow {
                        ExperienceTextField("URL", text: $item.url, onChange: onChange)
                    }
                }
            }

            ExperienceAddButton(title: ExperienceSectionKey.references.addButtonTitle) {
                items.append(ReferenceExperienceDraft())
                onChange()
            }
        }
    }
}

// MARK: - List Editors

private struct HighlightListEditor: View {
    let title: String
    @Binding var items: [HighlightDraft]
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
                    ExperienceTextEditor("Highlight", text: $item.text, onChange: onChange)
                }
            }

            Button("Add Highlight") {
                items.append(HighlightDraft())
                onChange()
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct VolunteerHighlightListEditor: View {
    @Binding var items: [VolunteerHighlightDraft]
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Highlights")
                .font(.headline)

            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
                    ExperienceTextEditor("Highlight", text: $item.text, onChange: onChange)
                }
            }

            Button("Add Highlight") {
                items.append(VolunteerHighlightDraft())
                onChange()
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ProjectHighlightListEditor: View {
    @Binding var items: [ProjectHighlightDraft]
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Highlights")
                .font(.headline)

            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
                    ExperienceTextEditor("Highlight", text: $item.text, onChange: onChange)
                }
            }

            Button("Add Highlight") {
                items.append(ProjectHighlightDraft())
                onChange()
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct CourseListEditor: View {
    @Binding var items: [CourseDraft]
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Courses")
                .font(.headline)

            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
                    ExperienceTextField("Course", text: $item.name, onChange: onChange)
                }
            }

            Button("Add Course") {
                items.append(CourseDraft())
                onChange()
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct KeywordListEditor: View {
    let title: String
    @Binding var items: [KeywordDraft]
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
                    ExperienceTextField("Keyword", text: $item.keyword, onChange: onChange)
                }
            }

            Button("Add Keyword") {
                items.append(KeywordDraft())
                onChange()
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct RoleListEditor: View {
    let title: String
    @Binding var items: [RoleDraft]
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach($items) { $item in
                ExperienceCard {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        onChange()
                    }
                } content: {
                    ExperienceTextField("Role", text: $item.role, onChange: onChange)
                }
            }

            Button("Add Role") {
                items.append(RoleDraft())
                onChange()
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Field helpers

private struct ExperienceFieldRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            content
        }
    }
}

private struct ExperienceTextField: View {
    let title: String
    @Binding var text: String
    var onChange: () -> Void

    init(_ title: String, text: Binding<String>, onChange: @escaping () -> Void) {
        self.title = title
        _text = text
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .onChange(of: text) { _, _ in onChange() }
    }
}

private struct ExperienceTextEditor: View {
    let title: String
    @Binding var text: String
    var onChange: () -> Void

    init(_ title: String, text: Binding<String>, onChange: @escaping () -> Void) {
        self.title = title
        _text = text
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 100)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .onChange(of: text) { _, _ in onChange() }
    }
}

@ViewBuilder
private func sectionContainer<Content: View>(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 16) {
        ExperienceSectionHeader(title, subtitle: subtitle)
        VStack(alignment: .leading, spacing: 16, content: content)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
