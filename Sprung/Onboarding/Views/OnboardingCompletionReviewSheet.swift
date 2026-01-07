import AppKit
import SwiftUI

/// A lightweight "wrap-up" screen shown when onboarding completes.
/// Keeps the interview window open long enough for the user to review key assets.
struct OnboardingCompletionReviewSheet: View {
    let coordinator: OnboardingInterviewCoordinator
    let onFinish: () -> Void

    @Environment(CoverRefStore.self) private var coverRefStore
    @Environment(ExperienceDefaultsStore.self) private var experienceDefaultsStore

    @State private var selectedTab: Tab = .summary

    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case knowledgeCards = "Knowledge Cards"
        case skills = "Skills"
        case writingContext = "Writing Context"
        case experienceDefaults = "Experience"
        case nextSteps = "Next Steps"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .summary: return "checkmark.circle"
            case .knowledgeCards: return "brain.head.profile"
            case .skills: return "star.fill"
            case .writingContext: return "doc.text"
            case .experienceDefaults: return "person.text.rectangle"
            case .nextSteps: return "arrow.right.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Onboarding Complete")
                    .font(.title2.weight(.semibold))
                Text("Review your assets before closing the interview.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Finish") {
                onFinish()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Tab bar with icons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Tab.allCases) { tab in
                        tabButton(tab)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case .summary:
                    summaryTab
                case .knowledgeCards:
                    knowledgeCardsTab
                case .skills:
                    skillsTab
                case .writingContext:
                    writingContextTab
                case .experienceDefaults:
                    experienceDefaultsTab
                case .nextSteps:
                    nextStepsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = selectedTab == tab
        let count = countFor(tab)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.caption)
                Text(tab.rawValue)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15))
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func countFor(_ tab: Tab) -> Int? {
        switch tab {
        case .summary, .nextSteps:
            return nil
        case .knowledgeCards:
            return coordinator.allKnowledgeCards.count
        case .skills:
            return coordinator.skillStore.approvedSkills.count
        case .writingContext:
            return coverRefStore.storedCoverRefs.count
        case .experienceDefaults:
            let defaults = experienceDefaultsStore.currentDefaults()
            return defaults.work.count + defaults.education.count + defaults.projects.count
        }
    }

    // MARK: - Summary Tab

    private var summaryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("What was created")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    summaryCard(
                        icon: "brain.head.profile",
                        title: "Knowledge Cards",
                        value: "\(coordinator.allKnowledgeCards.count)",
                        color: .purple
                    )
                    summaryCard(
                        icon: "star.fill",
                        title: "Skills",
                        value: "\(coordinator.skillStore.approvedSkills.count)",
                        color: .orange
                    )
                    summaryCard(
                        icon: "doc.text",
                        title: "Writing Sources",
                        value: "\(coverRefStore.storedCoverRefs.count)",
                        color: .blue
                    )

                    let defaults = experienceDefaultsStore.currentDefaults()
                    summaryCard(
                        icon: "briefcase",
                        title: "Work Entries",
                        value: "\(defaults.work.count)",
                        color: .green
                    )
                }

                Text("Quick Actions")
                    .font(.headline)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Button("Open Applicant Profile") {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .showApplicantProfile, object: nil)
                            _ = NSApp.sendAction(#selector(AppDelegate.showApplicantProfileWindow), to: nil, from: nil)
                        }
                    }
                    Button("Open Experience Editor") {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .showExperienceEditor, object: nil)
                            _ = NSApp.sendAction(#selector(AppDelegate.showExperienceEditorWindow), to: nil, from: nil)
                        }
                    }
                    Button("Browse Knowledge Cards") {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .toggleKnowledgeCards, object: nil)
                        }
                    }
                    Button("Browse Writing Context") {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .showWritingContextBrowser, object: nil)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func summaryCard(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold).monospacedDigit())
            }

            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Knowledge Cards Tab

    private var knowledgeCardsTab: some View {
        CompletionKnowledgeCardsTab(coordinator: coordinator)
    }

    // MARK: - Skills Tab

    private var skillsTab: some View {
        SkillsBankBrowser(skillStore: coordinator.skillStore, llmFacade: coordinator.llmFacade)
    }

    // MARK: - Writing Context Tab

    private var writingContextTab: some View {
        WritingContextBrowserTab(coverRefStore: coverRefStore)
    }

    // MARK: - Experience Defaults Tab

    private var experienceDefaultsTab: some View {
        ExperienceDefaultsBrowserTab(store: experienceDefaultsStore)
    }

    // MARK: - Next Steps Tab

    private var nextStepsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Next steps")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    nextStepRow(
                        number: 1,
                        title: "Review your assets",
                        description: "Browse the tabs above to verify knowledge cards, skills, and writing context look correct."
                    )
                    nextStepRow(
                        number: 2,
                        title: "Edit your profile",
                        description: "Open Applicant Profile to update your name, email, phone, and other contact details."
                    )
                    nextStepRow(
                        number: 3,
                        title: "Create a job application",
                        description: "Start a new job application to generate a tailored resume and cover letter."
                    )
                    nextStepRow(
                        number: 4,
                        title: "Export and apply",
                        description: "Export your customized resume as PDF and submit your application."
                    )
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private func nextStepRow(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Knowledge Cards Browser Tab (Read-Only for Completion)

private struct CompletionKnowledgeCardsTab: View {
    let coordinator: OnboardingInterviewCoordinator

    @State private var expandedCardIds: Set<UUID> = []
    @State private var searchText = ""
    @State private var selectedType: String?

    private var allCards: [KnowledgeCard] {
        coordinator.allKnowledgeCards
    }

    private var filteredCards: [KnowledgeCard] {
        var cards = allCards

        if !searchText.isEmpty {
            let search = searchText.lowercased()
            cards = cards.filter {
                $0.title.lowercased().contains(search) ||
                $0.organization?.lowercased().contains(search) == true ||
                $0.narrative.lowercased().contains(search)
            }
        }

        if let type = selectedType {
            cards = cards.filter { $0.cardType?.rawValue.lowercased() == type }
        }

        return cards
    }

    private var cardTypes: [String] {
        let types = Set(allCards.compactMap { $0.cardType?.rawValue.lowercased() })
        return ["employment", "project", "education", "skill", "other"].filter { types.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            if allCards.isEmpty {
                emptyState
            } else if filteredCards.isEmpty {
                noMatchesState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredCards) { card in
                            cardRow(card)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search cards...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    typeChip(nil, label: "All")
                    ForEach(cardTypes, id: \.self) { type in
                        typeChip(type, label: type.capitalized)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func typeChip(_ type: String?, label: String) -> some View {
        let isSelected = selectedType == type
        let count: Int
        if let type = type {
            count = allCards.filter { $0.cardType?.rawValue.lowercased() == type }.count
        } else {
            count = allCards.count
        }

        return Button(action: { selectedType = type }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.purple : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func cardRow(_ card: KnowledgeCard) -> some View {
        let isExpanded = expandedCardIds.contains(card.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedCardIds.remove(card.id)
                    } else {
                        expandedCardIds.insert(card.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: iconFor(card.cardType?.rawValue.lowercased() ?? "other"))
                        .font(.caption)
                        .foregroundStyle(colorFor(card.cardType?.rawValue.lowercased() ?? "other"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if let org = card.organization, !org.isEmpty {
                            Text(org)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if !card.technologies.isEmpty {
                        Text("\(card.technologies.count) skills")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent(card)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func expandedContent(_ card: KnowledgeCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.horizontal, 12)

            if let dateRange = card.dateRange {
                Label(dateRange, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }

            if !card.technologies.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(card.technologies.prefix(10), id: \.self) { tech in
                            Text(tech)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        if card.technologies.count > 10 {
                            Text("+\(card.technologies.count - 10)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            if !card.narrative.isEmpty {
                Text(card.narrative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .padding(.horizontal, 12)
            }

            Spacer().frame(height: 8)
        }
    }

    private func iconFor(_ type: String) -> String {
        switch type {
        case "employment", "job": return "briefcase.fill"
        case "project": return "folder.fill"
        case "education": return "graduationcap.fill"
        case "skill": return "star.fill"
        default: return "doc.fill"
        }
    }

    private func colorFor(_ type: String) -> Color {
        switch type {
        case "employment", "job": return .blue
        case "project": return .green
        case "education": return .orange
        case "skill": return .purple
        default: return .gray
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Knowledge Cards")
                .font(.title3.weight(.medium))
            Text("Knowledge cards are created from your uploaded documents")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No Matching Cards")
                .font(.headline)
            Button("Clear Filters") {
                searchText = ""
                selectedType = nil
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Writing Context Browser Tab

private struct WritingContextBrowserTab: View {
    let coverRefStore: CoverRefStore

    @State private var searchText = ""
    @State private var selectedType: CoverRefType?
    @State private var expandedIds: Set<String> = []

    private var allRefs: [CoverRef] {
        coverRefStore.storedCoverRefs
    }

    private var filteredRefs: [CoverRef] {
        var refs = allRefs

        if !searchText.isEmpty {
            let search = searchText.lowercased()
            refs = refs.filter {
                $0.name.lowercased().contains(search) ||
                $0.content.lowercased().contains(search)
            }
        }

        if let type = selectedType {
            refs = refs.filter { $0.type == type }
        }

        return refs
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            if allRefs.isEmpty {
                emptyState
            } else if filteredRefs.isEmpty {
                noMatchesState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredRefs) { ref in
                            refRow(ref)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search writing context...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    typeChip(nil, label: "All", count: allRefs.count)
                    typeChip(.writingSample, label: "Writing Samples", count: allRefs.filter { $0.type == .writingSample }.count)
                    typeChip(.backgroundFact, label: "Background Facts", count: allRefs.filter { $0.type == .backgroundFact }.count)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func typeChip(_ type: CoverRefType?, label: String, count: Int) -> some View {
        let isSelected = selectedType == type

        return Button(action: { selectedType = type }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func refRow(_ ref: CoverRef) -> some View {
        let isExpanded = expandedIds.contains(ref.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedIds.remove(ref.id)
                    } else {
                        expandedIds.insert(ref.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: ref.type == .writingSample ? "doc.text" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(ref.type == .writingSample ? .blue : .orange)

                    Text(ref.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer()

                    Text("\(ref.content.split(separator: " ").count) words")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if ref.isDossier {
                        Text("Dossier")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.horizontal, 12)

                    Text(ref.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(10)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Writing Context")
                .font(.title3.weight(.medium))
            Text("Writing samples and dossier entries will appear here")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No Matches")
                .font(.headline)
            Button("Clear Filters") {
                searchText = ""
                selectedType = nil
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Experience Defaults Browser Tab

private struct ExperienceDefaultsBrowserTab: View {
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
