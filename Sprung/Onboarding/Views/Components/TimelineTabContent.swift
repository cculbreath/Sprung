import SwiftUI
import SwiftyJSON

/// Unified timeline view that supports browse, editor, and validation modes.
/// Replaces both TimelineTabContent and TimelineCardEditorView with a single component.
struct TimelineTabContent: View {
    enum Mode {
        case browse      // Read-only tab view
        case editor      // LLM-triggered editing with Done button
        case validation  // Final approval with Confirm/Reject buttons
    }

    let coordinator: OnboardingInterviewCoordinator
    var mode: Mode = .browse
    var onValidationSubmit: ((String) -> Void)?
    var onSubmitChangesOnly: (() -> Void)?
    var onDoneWithTimeline: (() -> Void)?
    var onDoneWithSectionCards: (() -> Void)?

    // MARK: - State

    @State private var drafts: [TimelineEntryDraft] = []
    @State private var baselineCards: [TimelineCard] = []
    @State private var previousDraftIds: Set<String> = []
    @State private var hasChanges = false
    @State private var isSaving = false
    @State private var isLoadingFromCoordinator = false
    @State private var lastLoadedToken: Int = -1
    @State private var expandedEntryId: String?
    @State private var isReordering = false

    private var canEdit: Bool {
        mode == .editor || mode == .validation
    }

    private var experiences: [JSON] {
        coordinator.ui.skeletonTimeline?["experiences"].array ?? []
    }

    var body: some View {
        // Access timelineUIChangeToken in body to establish @Observable tracking
        let _ = coordinator.ui.timelineUIChangeToken
        // Access section cards tokens for @Observable tracking
        let _ = coordinator.ui.sectionCardsUIChangeToken
        let _ = coordinator.ui.publicationCardsUIChangeToken

        VStack(spacing: 0) {
            // Scrollable content area
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if canEdit {
                        header
                    }

                    // Timeline Cards list
                    if canEdit {
                        editableCardsList
                    } else {
                        browseCardsList
                    }

                    // Additional Sections (Awards, Publications, Languages, References)
                    if hasAdditionalSections {
                        additionalSectionsView
                    }
                }
                .padding(.horizontal, 4)
            }

            // Sticky footer (outside ScrollView)
            if canEdit || coordinator.ui.isSectionCardsEditorActive {
                Divider()
                footerButtons
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onAppear {
            if canEdit {
                loadFromCoordinator()
            }
        }
        .onChange(of: coordinator.ui.timelineUIChangeToken) { _, newToken in
            guard canEdit, mode == .editor else { return }
            guard !isSaving, newToken != lastLoadedToken else { return }

            if let newTimeline = coordinator.ui.skeletonTimeline {
                let state = TimelineCardAdapter.cards(from: newTimeline)
                let newCards = state.cards
                let needsConfirmation = !newCards.isEmpty && (baselineCards.isEmpty || newCards != baselineCards)

                isLoadingFromCoordinator = true
                baselineCards = state.cards
                drafts = TimelineCardAdapter.entryDrafts(from: state.cards)
                previousDraftIds = Set(drafts.map { $0.id })
                hasChanges = needsConfirmation
                lastLoadedToken = newToken
                isLoadingFromCoordinator = false

                Logger.info("🔄 TimelineTabContent: Loaded \(newCards.count) cards from token \(newToken)", category: .ai)
            }
        }
        .onChange(of: drafts) { _, newDrafts in
            guard !isLoadingFromCoordinator else { return }

            // Detect deletions and sync immediately
            let currentIds = Set(newDrafts.map { $0.id })
            let deletedIds = previousDraftIds.subtracting(currentIds)
            if !deletedIds.isEmpty {
                Task {
                    for deletedId in deletedIds {
                        Logger.info("🗑️ UI deletion detected: syncing card \(deletedId) deletion", category: .ai)
                        await coordinator.deleteTimelineCardFromUI(id: deletedId)
                    }
                }
            }
            previousDraftIds = currentIds
            hasChanges = TimelineCardAdapter.cards(from: newDrafts) != baselineCards
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timeline Entries")
                    .font(.title3.weight(.semibold))
                if mode == .editor {
                    Text("Click an entry to edit. Use Reorder to change order.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if mode == .validation {
                    Text("Review your timeline. Make any final changes before confirming.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if canEdit {
                Button(isReordering ? "Done Reordering" : "Reorder") {
                    withAnimation {
                        isReordering.toggle()
                        if isReordering {
                            expandedEntryId = nil  // Collapse all when reordering
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    withAnimation {
                        let newEntry = TimelineEntryDraft()
                        drafts.append(newEntry)
                        expandedEntryId = newEntry.id  // Auto-expand new entry
                    }
                } label: {
                    Label("Add Entry", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Browse Mode (Read-Only)

    private var browseCardsList: some View {
        Group {
            if experiences.isEmpty {
                emptyState
            } else {
                ForEach(Array(experiences.enumerated()), id: \.offset) { _, experience in
                    TimelineCardRow(experience: experience)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Timeline Cards",
            systemImage: "calendar.badge.clock",
            description: Text("Timeline cards will appear here as they're created during the interview.")
        )
        .frame(maxWidth: .infinity, minHeight: 180)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Edit Mode (Editable Cards)

    private var editableCardsList: some View {
        Group {
            if drafts.isEmpty {
                emptyEditState
            } else {
                ForEach(Array($drafts.enumerated()), id: \.element.id) { index, $entry in
                    TimelineEditableCard(
                        entry: $entry,
                        isExpanded: expandedEntryId == entry.id,
                        isReordering: isReordering,
                        canEdit: canEdit,
                        index: index,
                        totalCount: drafts.count,
                        onTap: {
                            withAnimation {
                                if expandedEntryId == entry.id {
                                    expandedEntryId = nil
                                } else {
                                    expandedEntryId = entry.id
                                }
                            }
                        },
                        onDelete: {
                            withAnimation {
                                if expandedEntryId == entry.id {
                                    expandedEntryId = nil
                                }
                                drafts.remove(at: index)
                            }
                        },
                        onMoveUp: {
                            guard index > 0 else { return }
                            withAnimation {
                                drafts.swapAt(index, index - 1)
                            }
                        },
                        onMoveDown: {
                            guard index < drafts.count - 1 else { return }
                            withAnimation {
                                drafts.swapAt(index, index + 1)
                            }
                        }
                    )
                }
            }
        }
    }

    private var emptyEditState: some View {
        ContentUnavailableView(
            "No Timeline Entries",
            systemImage: "calendar.badge.plus",
            description: Text("Add entries to build your experience timeline.")
        )
        .frame(maxWidth: .infinity, minHeight: 180)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Footer Buttons

    private var footerButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if mode == .editor {
                    editorModeButtons
                } else if mode == .validation {
                    validationModeButtons
                } else if coordinator.ui.isSectionCardsEditorActive {
                    sectionCardsButtons
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var sectionCardsButtons: some View {
        Spacer()

        Button {
            onDoneWithSectionCards?()
        } label: {
            Label("Done with Section Cards", systemImage: "checkmark.circle")
        }
        .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private var editorModeButtons: some View {
        if hasChanges {
            Button("Discard Changes", role: .cancel) {
                discardChanges()
            }
            .disabled(isSaving)

            Button {
                saveChanges()
            } label: {
                Label(isSaving ? "Saving…" : "Save Changes", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(isSaving)
        }

        Spacer()

        Button {
            doneWithTimeline()
        } label: {
            Label(isSaving ? "Saving…" : "Done with Timeline", systemImage: "checkmark.circle")
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSaving || drafts.isEmpty)
    }

    @ViewBuilder
    private var validationModeButtons: some View {
        Button("Reject", role: .destructive) {
            onValidationSubmit?("rejected")
        }

        if hasChanges {
            Button("Submit Changes Only") {
                submitChangesOnly()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Confirm with Changes") {
                onValidationSubmit?("confirmed_with_changes")
            }
            .buttonStyle(.borderedProminent)
        } else {
            Spacer()

            Button("Confirm") {
                onValidationSubmit?("confirmed")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func loadFromCoordinator() {
        if let syncTimeline = coordinator.ui.skeletonTimeline {
            let state = TimelineCardAdapter.cards(from: syncTimeline)
            isLoadingFromCoordinator = true
            baselineCards = state.cards
            drafts = TimelineCardAdapter.entryDrafts(from: state.cards)
            previousDraftIds = Set(drafts.map { $0.id })
            hasChanges = false
            isLoadingFromCoordinator = false
            lastLoadedToken = coordinator.ui.timelineUIChangeToken
            Logger.info("🔄 TimelineTabContent: Loaded \(state.cards.count) cards on appear", category: .ai)
        }
    }

    private func discardChanges() {
        withAnimation {
            isLoadingFromCoordinator = true
            drafts = TimelineCardAdapter.entryDrafts(from: baselineCards)
            hasChanges = false
            expandedEntryId = nil
            isLoadingFromCoordinator = false
        }
    }

    private func saveChanges() {
        guard hasChanges, !isSaving else { return }

        let updatedCards = TimelineCardAdapter.cards(from: drafts)
        let diff = TimelineDiffBuilder.diff(original: baselineCards, updated: updatedCards)

        guard !diff.isEmpty else {
            hasChanges = false
            return
        }

        isSaving = true

        Task { @MainActor in
            await coordinator.applyUserTimelineUpdate(cards: updatedCards, meta: nil, diff: diff)
            baselineCards = updatedCards
            hasChanges = false
            isSaving = false
        }
    }

    private func submitChangesOnly() {
        guard hasChanges, !isSaving else { return }

        let updatedCards = TimelineCardAdapter.cards(from: drafts)
        let diff = TimelineDiffBuilder.diff(original: baselineCards, updated: updatedCards)

        guard !diff.isEmpty else {
            hasChanges = false
            return
        }

        isSaving = true

        Task { @MainActor in
            await coordinator.applyUserTimelineUpdate(cards: updatedCards, meta: nil, diff: diff)
            baselineCards = updatedCards
            hasChanges = false
            isSaving = false
            onSubmitChangesOnly?()
        }
    }

    private func doneWithTimeline() {
        guard !isSaving else { return }
        isSaving = true

        let updatedCards = TimelineCardAdapter.cards(from: drafts)
        let diff = TimelineDiffBuilder.diff(original: baselineCards, updated: updatedCards)

        Task { @MainActor in
            if !diff.isEmpty {
                await coordinator.applyUserTimelineUpdate(cards: updatedCards, meta: nil, diff: diff)
                baselineCards = updatedCards
                hasChanges = false
            }
            isSaving = false
            onDoneWithTimeline?()
        }
    }

    // MARK: - Additional Sections (Awards, Publications, Languages, References)

    private var hasAdditionalSections: Bool {
        !coordinator.ui.sectionCards.isEmpty || !coordinator.ui.publicationCards.isEmpty
    }

    @ViewBuilder
    private var additionalSectionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Awards Section
            let awards = coordinator.ui.sectionCards.filter { $0.sectionType == .award }
            if !awards.isEmpty {
                AdditionalSectionGroup(
                    title: "Awards",
                    icon: "trophy",
                    color: .yellow,
                    entries: awards
                )
            }

            // Publications Section
            let publications = coordinator.ui.publicationCards
            if !publications.isEmpty {
                PublicationSectionGroup(
                    title: "Publications",
                    icon: "book.pages",
                    color: .indigo,
                    publications: publications
                )
            }

            // Languages Section
            let languages = coordinator.ui.sectionCards.filter { $0.sectionType == .language }
            if !languages.isEmpty {
                AdditionalSectionGroup(
                    title: "Languages",
                    icon: "globe",
                    color: .teal,
                    entries: languages
                )
            }

            // References Section
            let references = coordinator.ui.sectionCards.filter { $0.sectionType == .reference }
            if !references.isEmpty {
                AdditionalSectionGroup(
                    title: "References",
                    icon: "person.text.rectangle",
                    color: .mint,
                    entries: references
                )
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Additional Section Group View

struct AdditionalSectionGroup: View {
    let title: String
    let icon: String
    let color: Color
    let entries: [AdditionalSectionEntry]

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .frame(width: 20)

                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Text("(\(entries.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Cards
            if isExpanded {
                ForEach(entries, id: \.id) { entry in
                    AdditionalSectionCardRow(entry: entry, color: color)
                }
            }
        }
    }
}

struct AdditionalSectionCardRow: View {
    let entry: AdditionalSectionEntry
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    if let subtitle = entry.displaySubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Text(entry.sectionType.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12))
                    .foregroundStyle(color)
                    .cornerRadius(4)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

// MARK: - Publication Section Group View

struct PublicationSectionGroup: View {
    let title: String
    let icon: String
    let color: Color
    let publications: [PublicationCard]

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .frame(width: 20)

                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Text("(\(publications.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Cards
            if isExpanded {
                ForEach(publications, id: \.id) { publication in
                    PublicationCardRow(publication: publication, color: color)
                }
            }
        }
    }
}

struct PublicationCardRow: View {
    let publication: PublicationCard
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(publication.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)

                    if let subtitle = publication.displaySubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let authors = publication.authorString {
                        Text(authors)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Publication type badge (prefer bibtexType over sourceType)
                Text(publicationTypeLabel(publication))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12))
                    .foregroundStyle(color)
                    .cornerRadius(4)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    /// Label for publication type - prefer bibtexType (article, book) over sourceType
    private func publicationTypeLabel(_ publication: PublicationCard) -> String {
        if let bibtexType = publication.bibtexType, !bibtexType.isEmpty {
            return formatBibtexType(bibtexType)
        }
        // Fallback to generic "Publication" instead of sourceType
        return "Publication"
    }

    private func formatBibtexType(_ type: String) -> String {
        switch type.lowercased() {
        case "article": return "Article"
        case "inproceedings", "conference": return "Conference"
        case "book": return "Book"
        case "incollection": return "Chapter"
        case "phdthesis": return "PhD Thesis"
        case "mastersthesis": return "Thesis"
        case "techreport": return "Report"
        case "misc": return "Publication"
        default: return type.capitalized
        }
    }
}

// MARK: - TimelineCardRow (Read-Only Display)

struct TimelineCardRow: View {
    let experience: JSON

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(experience["title"].stringValue)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Text(experience["organization"].stringValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                experienceTypeBadge
            }

            HStack(spacing: 6) {
                if let location = experience["location"].string, !location.isEmpty {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }

                if let start = experience["start"].string {
                    Text(formatDate(start))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if experience["start"].string != nil {
                    Text("–")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                let end = experience["end"].string ?? ""
                Text(end.isEmpty ? "Present" : formatDate(end))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var experienceTypeBadge: some View {
        let type = experience["experienceType"].string ?? "work"
        let (color, label) = typeInfo(for: type)

        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .cornerRadius(4)
    }

    private func typeInfo(for type: String) -> (Color, String) {
        switch type {
        case "education": return (.purple, "Education")
        case "volunteer": return (.orange, "Volunteer")
        case "project": return (.green, "Project")
        default: return (.blue, "Work")
        }
    }

    private func formatDate(_ dateString: String) -> String {
        let components = dateString.split(separator: "-")
        guard let year = components.first else { return dateString }

        if components.count >= 2, let month = Int(components[1]) {
            let monthNames = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if month > 0, month < 13 {
                return "\(monthNames[month]) \(year)"
            }
        }

        return String(year)
    }
}
