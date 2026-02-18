//
//  TitleSetsBrowserTab.swift
//  Sprung
//
//  Interactive Title Set Generator for the Resource Browser.
//  Allows users to generate, lock, and refine professional identity word combinations.
//

import SwiftUI

/// Browser tab for generating and managing professional identity title sets.
/// Features an interactive generator with word locking and conversation history.
struct TitleSetsBrowserTab: View {
    let titleSetStore: TitleSetStore?
    let llmFacade: LLMFacade?
    let skills: [Skill]

    init(titleSetStore: TitleSetStore?, llmFacade: LLMFacade?, skills: [Skill] = []) {
        self.titleSetStore = titleSetStore
        self.llmFacade = llmFacade
        self.skills = skills
    }

    // Current generator state
    @State private var currentWords: [TitleWord] = [
        TitleWord(text: "", isLocked: false),
        TitleWord(text: "", isLocked: false),
        TitleWord(text: "", isLocked: false),
        TitleWord(text: "", isLocked: false)
    ]
    @State private var instructions: String = ""
    @State private var isGenerating: Bool = false
    @State private var aiComment: String?
    @State private var conversationHistory: [GenerationTurn] = []

    // Pending sets from bulk generation (not yet approved)
    @State private var pendingSets: [[TitleWord]] = []

    // Selection
    @State private var selectedSetId: UUID?

    var body: some View {
        HStack(spacing: 0) {
            // Left panel: Approved combinations
            approvedCombinationsPanel
                .frame(width: 340)

            Divider()

            // Right panel: Interactive generator
            generatorPanel
        }
    }

    // MARK: - Left Panel: Approved Combinations

    private var approvedCombinationsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pending section (only visible when there are pending sets)
            if !pendingSets.isEmpty {
                pendingSection
                Divider()
            }

            // Approved header
            HStack {
                Text("Approved Combinations")
                    .font(.headline)
                Spacer()
                Text("\(titleSetStore?.titleSetCount ?? 0)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.2), in: Capsule())
                    .foregroundStyle(.cyan)
            }
            .padding()

            Divider()

            // List of saved title sets
            if let store = titleSetStore, !store.allTitleSets.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.allTitleSets) { titleSet in
                            TitleSetBrowserRow(
                                titleSet: titleSet,
                                isSelected: selectedSetId == titleSet.id,
                                onSelect: { selectedSetId = titleSet.id },
                                onDelete: { deleteTitleSet(titleSet) },
                                onLoad: { loadTitleSet(titleSet) }
                            )
                        }
                    }
                    .padding()
                }
            } else {
                emptyStateView
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Pending Section

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pending Review")
                    .font(.headline)
                Spacer()
                Text("\(pendingSets.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
            }
            .padding()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(pendingSets.indices, id: \.self) { index in
                        PendingTitleSetRow(
                            words: pendingSets[index],
                            onApprove: { approvePendingSet(at: index) },
                            onReject: { rejectPendingSet(at: index) }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 200)
        }
        .background(Color.orange.opacity(0.05))
    }

    // MARK: - Pending Actions

    private func approvePendingSet(at index: Int) {
        guard let store = titleSetStore, index < pendingSets.count else { return }
        let words = pendingSets[index]
        let titleSet = TitleSetRecord(words: words, notes: "Bulk generated")
        store.add(titleSet)
        pendingSets.remove(at: index)
    }

    private func rejectPendingSet(at index: Int) {
        guard index < pendingSets.count else { return }
        pendingSets.remove(at: index)
    }

    private func deleteTitleSet(_ titleSet: TitleSetRecord) {
        titleSetStore?.delete(titleSet)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No Title Sets")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Generate your first set of professional identity words")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Right Panel: Generator

    private var generatorPanel: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 4) {
                Text("Title Set Generator")
                    .font(.title2.weight(.semibold))
                Text("Lock words to keep them, then generate new ones")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            // Word slots
            wordSlotsGrid

            // Instructions
            instructionsField

            // AI Comment (if any)
            if let comment = aiComment {
                aiCommentView(comment)
            }

            Spacer()

            // Action buttons
            actionButtons

            // Lock count
            Text("Locked: \(lockedCount) / 4 words")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom)
        }
        .padding()
    }

    // MARK: - Word Slots Grid

    private var wordSlotsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(currentWords.indices, id: \.self) { index in
                WordSlotView(
                    word: $currentWords[index],
                    index: index
                )
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Instructions Field

    private var instructionsField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Instructions (optional)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Add notes or instructions for this combination...", text: $instructions, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .lineLimit(2...4)
        }
        .padding(.horizontal)
    }

    // MARK: - AI Comment

    private func aiCommentView(_ comment: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.cyan)
            Text(comment)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Main actions
            HStack(spacing: 12) {
                Button {
                    Task { await generateWords() }
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Generate")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isGenerating || llmFacade == nil)

                Button {
                    saveCurrentSet()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Approve & Save")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!hasValidWords)
            }

            // Bulk generation
            HStack(spacing: 8) {
                ForEach([5, 10, 20], id: \.self) { count in
                    Button {
                        Task { await bulkGenerate(count: count) }
                    } label: {
                        Text("Generate \(count)")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .disabled(isGenerating || llmFacade == nil)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Computed Properties

    private var lockedCount: Int {
        currentWords.filter { $0.isLocked }.count
    }

    private var hasValidWords: Bool {
        currentWords.allSatisfy { !$0.text.isEmpty }
    }

    // MARK: - Actions

    private func loadTitleSet(_ titleSet: TitleSetRecord) {
        currentWords = titleSet.words
        conversationHistory = titleSet.history
        aiComment = titleSet.history.last?.aiComment
    }

    private func saveCurrentSet() {
        guard let store = titleSetStore, hasValidWords else { return }

        let titleSet = TitleSetRecord(
            words: currentWords,
            notes: instructions.isEmpty ? nil : instructions,
            history: conversationHistory
        )
        store.add(titleSet)

        // Clear and auto-generate next set
        clearGenerator()
        Task { await generateWords() }
    }

    private func clearGenerator() {
        currentWords = currentWords.map { word in
            TitleWord(text: word.isLocked ? word.text : "", isLocked: word.isLocked)
        }
        instructions = ""
        aiComment = nil
        conversationHistory = []
    }

    // MARK: - Generation (Service Wrappers)

    private func generateWords() async {
        guard let facade = llmFacade else { return }

        let service = TitleSetGenerationService(llmFacade: facade)
        isGenerating = true
        defer { isGenerating = false }

        do {
            let response = try await service.generate(
                currentWords: currentWords,
                instructions: instructions,
                conversationHistory: conversationHistory,
                approvedSets: titleSetStore?.allTitleSets ?? [],
                skills: skills
            )
            applyGenerationResponse(response)
        } catch let configError as TitleSetGenerationError {
            aiComment = configError.localizedDescription
        } catch {
            Logger.error("Title generation failed: \(error)", category: .ai)
            aiComment = "Generation failed. Please try again."
        }
    }

    private func bulkGenerate(count: Int) async {
        guard let facade = llmFacade else { return }

        let service = TitleSetGenerationService(llmFacade: facade)
        isGenerating = true
        defer { isGenerating = false }

        do {
            let response = try await service.bulkGenerate(
                count: count,
                currentWords: currentWords,
                instructions: instructions,
                approvedSets: titleSetStore?.allTitleSets ?? [],
                skills: skills
            )
            applyBulkResponse(response)
        } catch let configError as TitleSetGenerationError {
            aiComment = configError.localizedDescription
        } catch {
            Logger.error("Bulk title generation failed: \(error)", category: .ai)
            aiComment = "Bulk generation failed. Please try again."
        }
    }

    // MARK: - Response Application

    private func applyGenerationResponse(_ response: TitleGenerationResponse) {
        let lockedWords = currentWords.enumerated()
            .filter { $0.element.isLocked }
            .map { $0.element.text }
        let lockedTexts = Set(lockedWords)

        for (index, word) in response.words.prefix(4).enumerated() {
            currentWords[index].text = word
            currentWords[index].isLocked = lockedTexts.contains(word)
        }

        aiComment = response.comment

        let turn = GenerationTurn(
            userInstructions: instructions.isEmpty ? nil : instructions,
            lockedWordTexts: lockedWords,
            generatedWords: response.words,
            aiComment: response.comment
        )
        conversationHistory.append(turn)
    }

    private func applyBulkResponse(_ response: BulkTitleResponse) {
        let lockedTexts = Set(
            currentWords.filter { $0.isLocked && !$0.text.isEmpty }.map { $0.text }
        )

        for set in response.sets {
            let words = set.words.prefix(4).map { text in
                TitleWord(text: text, isLocked: lockedTexts.contains(text))
            }
            guard words.count == 4 else { continue }
            pendingSets.append(Array(words))
        }
    }
}
