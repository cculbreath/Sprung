// Sprung/App/Views/ToolbarButtons/CoverLetterGenerateButton.swift
import SwiftUI
struct CoverLetterGenerateButton: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(CoverLetterService.self) private var coverLetterService: CoverLetterService
    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore: KnowledgeCardStore
    @Environment(CandidateDossierStore.self) private var candidateDossierStore: CandidateDossierStore
    @State private var showCoverLetterModelSheet = false
    @State private var selectedCoverLetterModel = ""
    var body: some View {
        Button(action: {
            showCoverLetterModelSheet = true
        }, label: {
            Label {
                Text("Create Letter")
            } icon: {
                if coverLetterStore.isGeneratingCoverLetter {
                    Image("custom.append.page.badge.plus")
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
                    .font(.system(size: 14, weight: .light))                } else {
                    Image("custom.append.page.badge.plus")
                            .font(.system(size: 14, weight: .light))
                }
            }
        })
        .font(.system(size: 14, weight: .light))
        .buttonStyle( .automatic )
        .help("Generate Cover Letter")
        .disabled(jobAppStore.selectedApp?.selectedRes == nil)
        .sheet(isPresented: $showCoverLetterModelSheet) {
            if let jobApp = jobAppStore.selectedApp {
                GenerateCoverLetterView(
                    jobApp: jobApp,
                    onGenerate: { modelId, selectedRefs, kcInclusion, selectedCardIds in
                        selectedCoverLetterModel = modelId
                        showCoverLetterModelSheet = false
                        coverLetterStore.isGeneratingCoverLetter = true
                        Task {
                            await generateCoverLetter(
                                modelId: modelId,
                                selectedRefs: selectedRefs,
                                knowledgeCardInclusion: kcInclusion,
                                selectedKnowledgeCardIds: selectedCardIds
                            )
                        }
                    }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerGenerateCoverLetterButton)) { _ in
            // Programmatically trigger the button action (from menu commands)
            showCoverLetterModelSheet = true
        }
    }
    @MainActor
    private func generateCoverLetter(
        modelId: String,
        selectedRefs: [CoverRef],
        knowledgeCardInclusion: KnowledgeCardInclusion,
        selectedKnowledgeCardIds: Set<String>
    ) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            coverLetterStore.isGeneratingCoverLetter = false
            return
        }
        // Resolve knowledge cards based on inclusion mode
        let resolvedCards: [KnowledgeCard] = {
            switch knowledgeCardInclusion {
            case .all: return knowledgeCardStore.knowledgeCards
            case .selected: return knowledgeCardStore.knowledgeCards.filter { selectedKnowledgeCardIds.contains($0.id.uuidString) }
            case .none: return []
            }
        }()
        let dossierContext = candidateDossierStore.exportForCoverLetter()
        do {
            try await coverLetterService.generateNewCoverLetter(
                jobApp: jobApp,
                resume: resume,
                modelId: modelId,
                coverLetterStore: coverLetterStore,
                selectedRefs: selectedRefs,
                knowledgeCards: resolvedCards,
                knowledgeCardInclusion: knowledgeCardInclusion,
                selectedKnowledgeCardIds: selectedKnowledgeCardIds,
                dossierContext: dossierContext
            )
            coverLetterStore.isGeneratingCoverLetter = false
        } catch {
            Logger.error("Error generating cover letter: \(error.localizedDescription)")
            coverLetterStore.isGeneratingCoverLetter = false
        }
    }
}
