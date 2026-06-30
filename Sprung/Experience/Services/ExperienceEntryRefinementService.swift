//
//  ExperienceEntryRefinementService.swift
//  Sprung
//
//  Refines a single Experience Editor entry (work or project) by reusing the
//  Seed Generation Module's generators and prompts. The user's free-text
//  direction is fed to the generator as rejection feedback, and the entry's
//  current content as the "previous generation" — so the identical voice,
//  length, and forbidden-formula rules apply, with no prompt duplication.
//

import Foundation

/// Which experience section a refine targets. Only sections backed by a real
/// seed-generation generator are refinable.
enum ExperienceRefineKind: Equatable {
    case work
    case projects

    var operationName: String {
        switch self {
        case .work: return "Refining work highlights"
        case .projects: return "Refining project content"
        }
    }
}

/// Neutral content shuttled between an entry, the LLM, and the review sheet.
/// `description`/`keywords` are nil for work (which only has highlights).
struct ExperienceRefineContent: Equatable {
    var description: String?
    var highlights: [String]
    var keywords: [String]?
}

/// A pending refine, used to drive the review sheet from the editor.
struct ExperienceRefineRequest: Identifiable {
    let id = UUID()
    let entryID: UUID
    let kind: ExperienceRefineKind
    let title: String
}

enum ExperienceRefinementError: LocalizedError {
    case unexpectedContent

    var errorDescription: String? {
        switch self {
        case .unexpectedContent:
            return "The model returned content in an unexpected shape."
        }
    }
}

/// Drives single-entry refinement using the SGM generators. Stateless beyond its
/// injected stores — one instance is shared across the Experience Editor.
@Observable
@MainActor
final class ExperienceEntryRefinementService {
    private let knowledgeCardStore: KnowledgeCardStore
    private let skillStore: SkillStore
    private let applicantProfileStore: ApplicantProfileStore
    private let coverRefStore: CoverRefStore
    private let candidateDossierStore: CandidateDossierStore
    private let titleSetStore: TitleSetStore
    private let llmFacade: LLMFacade

    init(
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore,
        applicantProfileStore: ApplicantProfileStore,
        coverRefStore: CoverRefStore,
        candidateDossierStore: CandidateDossierStore,
        titleSetStore: TitleSetStore,
        llmFacade: LLMFacade
    ) {
        self.knowledgeCardStore = knowledgeCardStore
        self.skillStore = skillStore
        self.applicantProfileStore = applicantProfileStore
        self.coverRefStore = coverRefStore
        self.candidateDossierStore = candidateDossierStore
        self.titleSetStore = titleSetStore
        self.llmFacade = llmFacade
    }

    /// Revise one entry. `current` seeds the generator's "previous generation";
    /// `draft` is the live editor state, snapshotted so unsaved edits to the
    /// entry's metadata reach the prompt. `feedback` is the user's direction
    /// (empty → "produce a fresh alternative", per the generator's contract).
    func refine(
        kind: ExperienceRefineKind,
        entryID: UUID,
        current: ExperienceRefineContent,
        draft: ExperienceDefaultsDraft,
        feedback: String
    ) async throws -> ExperienceRefineContent {
        // Resolve user-selected backend + model — no silent fallback. A missing
        // value surfaces the picker via ModelConfigurationError.settingKey.
        guard let backendString = UserDefaults.standard.string(forKey: "seedGenerationBackend"),
              !backendString.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "seedGenerationBackend",
                operationName: kind.operationName
            )
        }
        let backend: LLMFacade.Backend = backendString == "anthropic" ? .anthropic : .openRouter
        let modelKey = backend == .anthropic ? "seedGenerationAnthropicModelId" : "seedGenerationOpenRouterModelId"
        let modelId = try ModelConfigResolver.resolve(key: modelKey, operation: kind.operationName)

        // Build the generation context from an in-memory snapshot of the live draft.
        let snapshot = ExperienceDefaults()
        draft.apply(to: snapshot)
        guard let context = await SeedGenerationContextBuilder.build(
            defaults: snapshot,
            knowledgeCardStore: knowledgeCardStore,
            skillStore: skillStore,
            applicantProfileStore: applicantProfileStore,
            coverRefStore: coverRefStore,
            candidateDossierStore: candidateDossierStore,
            titleSetStore: titleSetStore
        ) else {
            throw ExperienceRefinementError.unexpectedContent
        }

        let preamble = PromptCacheService(backend: backend).buildPreamble(context: context)
        let config = GeneratorExecutionConfig(
            llmFacade: llmFacade,
            modelId: modelId,
            backend: backend,
            preamble: preamble,
            options: GenerationOptions.load()
        )

        let targetId = entryID.uuidString
        let generator: any SectionGenerator
        let section: ExperienceSectionKey
        let originalContent: GeneratedContent
        switch kind {
        case .work:
            generator = WorkHighlightsGenerator()
            section = .work
            originalContent = GeneratedContent(
                type: .workHighlights(targetId: targetId, highlights: current.highlights)
            )
        case .projects:
            generator = ProjectsGenerator()
            section = .projects
            originalContent = GeneratedContent(
                type: .projectDescription(
                    targetId: targetId,
                    description: current.description ?? "",
                    highlights: current.highlights,
                    keywords: current.keywords ?? []
                )
            )
        }

        let task = GenerationTask(
            section: section,
            targetId: targetId,
            displayName: "Refine: \(targetId)"
        )
        let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await generator.regenerate(
            task: task,
            originalContent: originalContent,
            feedback: trimmed.isEmpty ? nil : trimmed,
            context: context,
            config: config
        )

        switch result.type {
        case .workHighlights(_, let highlights):
            return ExperienceRefineContent(description: nil, highlights: highlights, keywords: nil)
        case .projectDescription(_, let description, let highlights, let keywords):
            return ExperienceRefineContent(description: description, highlights: highlights, keywords: keywords)
        default:
            throw ExperienceRefinementError.unexpectedContent
        }
    }
}
