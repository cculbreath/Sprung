import AppKit
import SwiftUI

/// Unified browser for Knowledge Cards, Writing Samples, and Skills Bank.
/// Uses generic CoverflowBrowser for cards, list view for skills.
struct UnifiedReferenceBrowserOverlay: View {
    @Binding var isPresented: Bool

    enum Tab: String, CaseIterable, Identifiable {
        case knowledge = "Knowledge Cards"
        case writing = "Writing Samples"
        case skills = "Skills"
        case titleSets = "Title Sets"
        case dossier = "Dossier"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .knowledge: return "brain.head.profile"
            case .writing: return "doc.text"
            case .skills: return "star.fill"
            case .titleSets: return "person.crop.rectangle.stack"
            case .dossier: return "person.text.rectangle"
            }
        }

        var accentColor: Color {
            switch self {
            case .knowledge: return .purple
            case .writing: return .blue
            case .skills: return .orange
            case .titleSets: return .cyan
            case .dossier: return .green
            }
        }

        /// Short label for segmented picker
        var shortLabel: String {
            switch self {
            case .knowledge: return "Knowledge"
            case .writing: return "Writing"
            case .skills: return "Skills"
            case .titleSets: return "Titles"
            case .dossier: return "Dossier"
            }
        }
    }

    /// Initial tab to display when opening the browser
    var initialTab: Tab = .knowledge

    @State private var selectedTab: Tab = .knowledge

    // Knowledge Cards
    @Binding var knowledgeCards: [KnowledgeCard]
    let knowledgeCardStore: KnowledgeCardStore
    let onKnowledgeCardUpdated: (KnowledgeCard) -> Void
    let onKnowledgeCardDeleted: (KnowledgeCard) -> Void
    let onKnowledgeCardAdded: (KnowledgeCard) -> Void

    // Writing Samples (CoverRef)
    @Binding var writingSamples: [CoverRef]
    let onWritingSampleUpdated: (CoverRef) -> Void
    let onWritingSampleDeleted: (CoverRef) -> Void
    let onWritingSampleAdded: (CoverRef) -> Void

    // Skills Store (SwiftData-backed)
    let skillStore: SkillStore?

    // Dossier store (SwiftData-backed)
    let dossierStore: CandidateDossierStore?

    // Title Set store
    let titleSetStore: TitleSetStore?

    // Optional LLM for analysis
    let llmFacade: LLMFacade?

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            tabContent
        }
        .frame(width: 780, height: 740)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 20)
        .focusable()
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onAppear {
            selectedTab = initialTab
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: selectedTab.icon)
                    .font(.title2)
                    .foregroundStyle(selectedTab.accentColor)

                Text("Reference Browser")
                    .font(.title2.weight(.semibold))

                Spacer()

                exportMenu

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Tab picker - use simple text labels for segmented style
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text("\(tab.shortLabel) (\(countFor(tab)))")
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(20)
    }

    private func countFor(_ tab: Tab) -> Int {
        switch tab {
        case .knowledge: return knowledgeCards.count
        case .writing: return writingSamples.count
        case .skills: return skillStore?.skills.count ?? 0
        case .titleSets: return titleSetStore?.titleSetCount ?? 0
        case .dossier: return dossierStore?.dossier != nil ? 1 : 0
        }
    }

    private var exportMenu: some View {
        Menu {
            Button(action: { exportToJSON(knowledgeCards, filename: "knowledge-cards.json") }) {
                Label("Export Knowledge Cards", systemImage: "brain.head.profile")
            }
            Button(action: { exportToJSON(writingSamples, filename: "writing-samples.json") }) {
                Label("Export Writing Samples", systemImage: "doc.text")
            }
            if let store = skillStore {
                Button(action: { exportToJSON(store.skills, filename: "skills.json") }) {
                    Label("Export Skills", systemImage: "star.fill")
                }
            }
            if let store = titleSetStore, store.hasTitleSets {
                Button(action: { exportTitleSets(store.allTitleSets) }) {
                    Label("Export Title Sets", systemImage: "person.crop.rectangle.stack")
                }
            }
            Divider()
            Button(action: exportAll) {
                Label("Export All", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.title3)
        }
        .menuStyle(.borderlessButton)
    }

    private func exportTitleSets(_ titleSets: [TitleSetRecord]) {
        // Convert to exportable format
        let exportable = titleSets.map { record in
            TitleSetExport(
                id: record.id.uuidString,
                words: record.words.map { $0.text },
                notes: record.notes,
                createdAt: record.createdAt
            )
        }
        exportToJSON(exportable, filename: "title-sets.json")
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .knowledge:
            KnowledgeCardsBrowserTab(
                cards: $knowledgeCards,
                knowledgeCardStore: knowledgeCardStore,
                onCardUpdated: onKnowledgeCardUpdated,
                onCardDeleted: onKnowledgeCardDeleted,
                onCardAdded: onKnowledgeCardAdded,
                llmFacade: llmFacade
            )
        case .writing:
            WritingSamplesBrowserTab(
                cards: $writingSamples,
                onCardUpdated: onWritingSampleUpdated,
                onCardDeleted: onWritingSampleDeleted,
                onCardAdded: onWritingSampleAdded
            )
        case .skills:
            SkillsBankBrowser(skillStore: skillStore, llmFacade: llmFacade)
        case .titleSets:
            TitleSetsBrowserTab(
                titleSetStore: titleSetStore,
                llmFacade: llmFacade,
                skills: skillStore?.skills ?? []
            )
        case .dossier:
            DossierBrowserTab(dossierStore: dossierStore)
        }
    }

    // MARK: - Export

    private func exportToJSON<T: Encodable>(_ data: T, filename: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = filename

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let jsonData = try encoder.encode(data)
                    try jsonData.write(to: url)
                } catch {
                    Logger.error("Export failed: \(error)", category: .general)
                }
            }
        }
    }

    private func exportAll() {
        let titleSetExports = (titleSetStore?.allTitleSets ?? []).map { record in
            TitleSetExport(
                id: record.id.uuidString,
                words: record.words.map { $0.text },
                notes: record.notes,
                createdAt: record.createdAt
            )
        }
        let bundle = ReferenceBundleExport(
            knowledgeCards: knowledgeCards,
            writingSamples: writingSamples,
            skills: skillStore?.skills ?? [],
            titleSets: titleSetExports,
            dossier: dossierStore?.dossier
        )
        exportToJSON(bundle, filename: "all-references.json")
    }
}

// MARK: - Dossier Browser Tab

/// Browser tab for candidate dossier
private struct DossierBrowserTab: View {
    let dossierStore: CandidateDossierStore?

    @State private var showEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with edit button
                HStack {
                    Image(systemName: "person.text.rectangle")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("Candidate Dossier")
                        .font(.title3.weight(.semibold))

                    Spacer()

                    if dossierStore != nil {
                        Button {
                            showEditor = true
                        } label: {
                            Label("Edit Dossier", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Content based on what's available
                if let store = dossierStore, let dossier = store.dossier {
                    dossierContent(dossier)
                } else {
                    emptyState
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showEditor) {
            if let store = dossierStore {
                CandidateDossierEditorView()
                    .environment(store)
            }
        }
    }

    private func dossierContent(_ dossier: CandidateDossier) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status bar
            HStack(spacing: 12) {
                Text("\(dossier.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if dossier.isComplete {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("Complete")
                            .font(.caption)
                    }
                    .foregroundStyle(.green)
                } else if !dossier.validationErrors.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("\(dossier.validationErrors.count) issue\(dossier.validationErrors.count == 1 ? "" : "s")")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }

                Spacer()

                Text("Updated \(dossier.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            // Job Search Context
            dossierField(title: "Job Search Context", content: dossier.jobSearchContext, required: true)

            // Strengths
            if let strengths = dossier.strengthsToEmphasize, !strengths.isEmpty {
                dossierField(title: "Strengths to Emphasize", content: strengths, required: false)
            }

            // Pitfalls
            if let pitfalls = dossier.pitfallsToAvoid, !pitfalls.isEmpty {
                dossierField(title: "Pitfalls to Avoid", content: pitfalls, required: false)
            }

            // Preferences
            if let prefs = dossier.workArrangementPreferences, !prefs.isEmpty {
                dossierField(title: "Work Arrangement", content: prefs, required: false)
            }

            if let avail = dossier.availability, !avail.isEmpty {
                dossierField(title: "Availability", content: avail, required: false)
            }

            // Private fields (shown with lock icon)
            if let circumstances = dossier.uniqueCircumstances, !circumstances.isEmpty {
                dossierField(title: "Unique Circumstances", content: circumstances, required: false, isPrivate: true)
            }

            if let notes = dossier.interviewerNotes, !notes.isEmpty {
                dossierField(title: "Interviewer Notes", content: notes, required: false, isPrivate: true)
            }
        }
    }

    private func dossierField(title: String, content: String, required: Bool, isPrivate: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                if required {
                    Text("Required")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }

                if isPrivate {
                    HStack(spacing: 2) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                        Text("Private")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(content.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(content)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Dossier")
                .font(.title3.weight(.medium))

            if dossierStore != nil {
                Text("Create a dossier to capture strategic positioning for your job search")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    showEditor = true
                } label: {
                    Label("Create Dossier", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            } else {
                Text("Complete an onboarding interview to capture dossier notes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Export Types

private struct TitleSetExport: Codable {
    let id: String
    let words: [String]
    let notes: String?
    let createdAt: Date
}

private struct ReferenceBundleExport: Codable {
    let knowledgeCards: [KnowledgeCard]
    let writingSamples: [CoverRef]
    let skills: [Skill]
    let titleSets: [TitleSetExport]
    let dossier: CandidateDossier?
    let exportedAt: Date

    init(knowledgeCards: [KnowledgeCard], writingSamples: [CoverRef], skills: [Skill], titleSets: [TitleSetExport], dossier: CandidateDossier?) {
        self.knowledgeCards = knowledgeCards
        self.writingSamples = writingSamples
        self.skills = skills
        self.titleSets = titleSets
        self.dossier = dossier
        self.exportedAt = Date()
    }
}
