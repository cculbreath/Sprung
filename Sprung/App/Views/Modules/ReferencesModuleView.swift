//
//  ReferencesModuleView.swift
//  Sprung
//
//  References module - unified browser for all reference data types.
//

import AppKit
import SwiftUI

/// References module - unified browser matching Reference Browser with all 5 data types
struct ReferencesModuleView: View {
    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore
    @Environment(CoverRefStore.self) private var coverRefStore
    @Environment(SkillStore.self) private var skillStore
    @Environment(TitleSetStore.self) private var titleSetStore
    @Environment(CandidateDossierStore.self) private var dossierStore
    @Environment(LLMFacade.self) private var llmFacade

    enum Tab: String, CaseIterable, Identifiable {
        case knowledge = "Knowledge"
        case writing = "Writing"
        case skills = "Skills"
        case titles = "Titles"
        case dossier = "Dossier"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .knowledge: return "brain.head.profile"
            case .writing: return "doc.text"
            case .skills: return "star.fill"
            case .titles: return "person.crop.rectangle.stack"
            case .dossier: return "person.text.rectangle"
            }
        }

        var accentColor: Color {
            switch self {
            case .knowledge: return .purple
            case .writing: return .blue
            case .skills: return .orange
            case .titles: return .cyan
            case .dossier: return .green
            }
        }
    }

    @State private var selectedTab: Tab = .knowledge

    var body: some View {
        VStack(spacing: 0) {
            // Fixed-height module header with pill picker
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: selectedTab.icon)
                        .font(.title2)
                        .foregroundStyle(selectedTab.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("References")
                            .font(.headline)
                        Text("Browse and manage your reference data")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    exportMenu
                }
                .padding(.horizontal)
                .padding(.top, 12)

                // Pill-style tab picker
                HStack(spacing: 4) {
                    ForEach(Tab.allCases) { tab in
                        TabPill(
                            tab: tab,
                            count: countFor(tab),
                            isSelected: selectedTab == tab,
                            action: { selectedTab = tab }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(.windowBackgroundColor))
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Tab content fills remaining space
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToReferencesTab)) { notification in
            if let tabString = notification.userInfo?["tab"] as? String,
               let tab = Tab(rawValue: tabString) {
                selectedTab = tab
            }
        }
    }

    // MARK: - Export

    private var exportMenu: some View {
        Menu {
            Button(action: { exportToJSON(knowledgeCardStore.knowledgeCards, filename: "knowledge-cards.json") }) {
                Label("Export Knowledge Cards", systemImage: "brain.head.profile")
            }
            Button(action: { exportToJSON(coverRefStore.storedCoverRefs, filename: "writing-samples.json") }) {
                Label("Export Writing Samples", systemImage: "doc.text")
            }
            Button(action: { exportToJSON(skillStore.skills, filename: "skills.json") }) {
                Label("Export Skills", systemImage: "star.fill")
            }
            if titleSetStore.hasTitleSets {
                Button(action: exportTitleSets) {
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
        .help("Export reference data as JSON")
    }

    private func exportToJSON<T: Encodable>(_ data: T, filename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: url)
        } catch {
            Logger.error("Export failed: \(error.localizedDescription)", category: .ai)
        }
    }

    private func exportTitleSets() {
        let exportable = titleSetStore.allTitleSets.map { record in
            TitleSetExport(
                id: record.id.uuidString,
                words: record.words.map { $0.text },
                notes: record.notes,
                createdAt: record.createdAt
            )
        }
        exportToJSON(exportable, filename: "title-sets.json")
    }

    private func exportAll() {
        let titleSetExports = titleSetStore.allTitleSets.map { record in
            TitleSetExport(
                id: record.id.uuidString,
                words: record.words.map { $0.text },
                notes: record.notes,
                createdAt: record.createdAt
            )
        }
        let bundle = ReferenceBundleExport(
            knowledgeCards: knowledgeCardStore.knowledgeCards,
            writingSamples: coverRefStore.storedCoverRefs,
            skills: skillStore.skills,
            titleSets: titleSetExports,
            dossier: dossierStore.dossier
        )
        exportToJSON(bundle, filename: "all-references.json")
    }

    private func countFor(_ tab: Tab) -> Int {
        switch tab {
        case .knowledge: return knowledgeCardStore.knowledgeCards.count
        case .writing: return coverRefStore.storedCoverRefs.count
        case .skills: return skillStore.skills.count
        case .titles: return titleSetStore.titleSetCount
        case .dossier: return dossierStore.dossier != nil ? 1 : 0
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .knowledge:
            KnowledgeCardsBrowserTab(
                cards: Binding(
                    get: { knowledgeCardStore.knowledgeCards },
                    set: { _ in }
                ),
                knowledgeCardStore: knowledgeCardStore,
                onCardUpdated: { card in knowledgeCardStore.update(card) },
                onCardDeleted: { card in knowledgeCardStore.delete(card) },
                onCardAdded: { card in knowledgeCardStore.add(card) },
                llmFacade: llmFacade
            )

        case .writing:
            WritingSamplesBrowserTab(
                cards: Binding(
                    get: { coverRefStore.storedCoverRefs },
                    set: { _ in }
                ),
                onCardUpdated: { _ in coverRefStore.saveContext() },
                onCardDeleted: { ref in coverRefStore.deleteCoverRef(ref) },
                onCardAdded: { ref in coverRefStore.addCoverRef(ref) }
            )

        case .skills:
            SkillsBankBrowser(skillStore: skillStore, llmFacade: llmFacade)

        case .titles:
            TitleSetsBrowserTab(
                titleSetStore: titleSetStore,
                llmFacade: llmFacade,
                skills: skillStore.skills
            )

        case .dossier:
            DossierBrowserTabInline(dossierStore: dossierStore)
        }
    }
}

// MARK: - Tab Pill

private struct TabPill: View {
    let tab: ReferencesModuleView.Tab
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(tab.rawValue)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("(\(count))")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? tab.accentColor : Color.clear)
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline Dossier Browser Tab

private struct DossierBrowserTabInline: View {
    let dossierStore: CandidateDossierStore

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

                    Button {
                        showEditor = true
                    } label: {
                        Label("Edit Dossier", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                }

                // Content based on what's available
                if let dossier = dossierStore.dossier {
                    dossierContent(dossier)
                } else {
                    emptyState
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showEditor) {
            CandidateDossierEditorView()
                .environment(dossierStore)
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

            // Private fields
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
