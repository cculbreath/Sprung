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
        case dossier = "Dossier"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .knowledge: return "brain.head.profile"
            case .writing: return "doc.text"
            case .skills: return "star.fill"
            case .dossier: return "person.text.rectangle"
            }
        }

        var accentColor: Color {
            switch self {
            case .knowledge: return .purple
            case .writing: return .blue
            case .skills: return .orange
            case .dossier: return .green
            }
        }

        /// Short label for segmented picker
        var shortLabel: String {
            switch self {
            case .knowledge: return "Knowledge"
            case .writing: return "Writing"
            case .skills: return "Skills"
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

    // Dossier notes
    let dossierNotes: String?

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
        case .dossier: return dossierNotes?.isEmpty == false ? 1 : 0
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
        case .dossier:
            DossierBrowserTab(notes: dossierNotes)
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
        let bundle = ReferenceBundleExport(
            knowledgeCards: knowledgeCards,
            writingSamples: writingSamples,
            skills: skillStore?.skills ?? [],
            dossierNotes: dossierNotes
        )
        exportToJSON(bundle, filename: "all-references.json")
    }
}

// MARK: - Dossier Browser Tab

/// Simple browser for dossier notes
private struct DossierBrowserTab: View {
    let notes: String?

    var body: some View {
        ScrollView {
            if let notes = notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "person.text.rectangle")
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text("Dossier Notes")
                            .font(.title3.weight(.semibold))
                        Spacer()
                    }

                    Text(notes)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(20)
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Dossier Notes")
                .font(.title3.weight(.medium))
            Text("Complete an onboarding interview to capture dossier notes")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Export Bundle

private struct ReferenceBundleExport: Codable {
    let knowledgeCards: [KnowledgeCard]
    let writingSamples: [CoverRef]
    let skills: [Skill]
    let dossierNotes: String?
    let exportedAt: Date

    init(knowledgeCards: [KnowledgeCard], writingSamples: [CoverRef], skills: [Skill], dossierNotes: String?) {
        self.knowledgeCards = knowledgeCards
        self.writingSamples = writingSamples
        self.skills = skills
        self.dossierNotes = dossierNotes
        self.exportedAt = Date()
    }
}
