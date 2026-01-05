import AppKit
import SwiftUI

/// Unified browser for Knowledge Cards, Writing Samples, and Skills Bank.
/// Uses generic CoverflowBrowser for cards, list view for skills.
struct UnifiedReferenceBrowserOverlay: View {
    @Binding var isPresented: Bool

    enum Tab: String, CaseIterable, Identifiable {
        case knowledge = "Knowledge"
        case writing = "Writing"
        case skills = "Skills"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .knowledge: return "brain.head.profile"
            case .writing: return "doc.text"
            case .skills: return "star.fill"
            }
        }

        var accentColor: Color {
            switch self {
            case .knowledge: return .purple
            case .writing: return .blue
            case .skills: return .orange
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

    // Skills Bank
    let skillBank: SkillBank?

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

            // Tab picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                        Text(tab.rawValue)
                        Text("(\(countFor(tab)))")
                            .foregroundStyle(.secondary)
                    }
                    .tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(20)
    }

    private func countFor(_ tab: Tab) -> Int {
        switch tab {
        case .knowledge: return knowledgeCards.count
        case .writing: return writingSamples.count
        case .skills: return skillBank?.skills.count ?? 0
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
            if let bank = skillBank {
                Button(action: { exportToJSON(bank, filename: "skills-bank.json") }) {
                    Label("Export Skills Bank", systemImage: "star.fill")
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
            SkillsBankBrowser(skillBank: skillBank)
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
            skillBank: skillBank
        )
        exportToJSON(bundle, filename: "all-references.json")
    }
}

private struct ReferenceBundleExport: Codable {
    let knowledgeCards: [KnowledgeCard]
    let writingSamples: [CoverRef]
    let skillBank: SkillBank?
    let exportedAt: Date

    init(knowledgeCards: [KnowledgeCard], writingSamples: [CoverRef], skillBank: SkillBank?) {
        self.knowledgeCards = knowledgeCards
        self.writingSamples = writingSamples
        self.skillBank = skillBank
        self.exportedAt = Date()
    }
}
