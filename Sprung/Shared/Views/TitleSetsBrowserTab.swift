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

    // Current generator state
    @State private var currentWords: [TitleWord] = [
        TitleWord(text: "", isLocked: false),
        TitleWord(text: "", isLocked: false),
        TitleWord(text: "", isLocked: false),
        TitleWord(text: "", isLocked: false)
    ]
    @State private var instructions: String = ""
    @State private var orderUnlocked: Bool = true
    @State private var isGenerating: Bool = false
    @State private var aiComment: String?
    @State private var conversationHistory: [GenerationTurn] = []

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
            // Header
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
                                onDelete: { store.delete(titleSet) },
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

            // Order toggle
            orderToggle

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

    // MARK: - Order Toggle

    private var orderToggle: some View {
        Button {
            orderUnlocked.toggle()
        } label: {
            HStack {
                Image(systemName: orderUnlocked ? "shuffle" : "arrow.right")
                Text(orderUnlocked ? "Order Unlocked" : "Order Fixed")
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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

        // Clear for next generation
        clearGenerator()
    }

    private func clearGenerator() {
        currentWords = currentWords.map { word in
            TitleWord(text: word.isLocked ? word.text : "", isLocked: word.isLocked)
        }
        instructions = ""
        aiComment = nil
        conversationHistory = []
    }

    private func generateWords() async {
        guard let facade = llmFacade else { return }

        isGenerating = true
        defer { isGenerating = false }

        // Build context from conversation history
        let historyContext = buildHistoryContext()

        // Build locked words list
        let lockedWords = currentWords.enumerated()
            .filter { $0.element.isLocked }
            .map { (index: $0.offset, word: $0.element.text) }

        let lockedDescription = lockedWords.isEmpty
            ? "No words are locked."
            : "Locked words (keep these): " + lockedWords.map { "Position \($0.index + 1): \($0.word)" }.joined(separator: ", ")

        let prompt = """
            Generate professional identity words for a resume title line.

            \(historyContext)

            Current state:
            \(lockedDescription)

            \(instructions.isEmpty ? "" : "User instructions: \(instructions)")

            Generate \(4 - lockedWords.count) new professional identity words for the unlocked positions.
            These should be single words or short phrases like "Physicist", "Software Developer", "Educator", "Machinist".
            They should work together as a cohesive professional identity.

            \(orderUnlocked ? "The order can be rearranged for best flow." : "Maintain the position order.")

            Return JSON:
            {
                "words": ["word1", "word2", "word3", "word4"],
                "comment": "Brief suggestion or observation about this combination"
            }

            Include all 4 words in the response, keeping locked words in their positions.
            """

        do {
            let response: TitleGenerationResponse = try await facade.executeStructuredWithDictionarySchema(
                prompt: prompt,
                modelId: getModelId(),
                as: TitleGenerationResponse.self,
                schema: [
                    "type": "object",
                    "properties": [
                        "words": ["type": "array", "items": ["type": "string"]],
                        "comment": ["type": "string"]
                    ],
                    "required": ["words", "comment"],
                    "additionalProperties": false
                ],
                schemaName: "title_generation"
            )

            // Update words
            for (index, word) in response.words.prefix(4).enumerated() {
                if !currentWords[index].isLocked {
                    currentWords[index].text = word
                }
            }

            // Update AI comment
            aiComment = response.comment

            // Add to conversation history
            let turn = GenerationTurn(
                userInstructions: instructions.isEmpty ? nil : instructions,
                lockedWordTexts: lockedWords.map { $0.word },
                generatedWords: response.words,
                aiComment: response.comment
            )
            conversationHistory.append(turn)

        } catch {
            Logger.error("Title generation failed: \(error)", category: .ai)
            aiComment = "Generation failed. Please try again."
        }
    }

    private func bulkGenerate(count: Int) async {
        guard let store = titleSetStore, let facade = llmFacade else { return }

        isGenerating = true
        defer { isGenerating = false }

        let prompt = """
            Generate \(count) distinct sets of 4 professional identity words for resume title lines.

            Each set should:
            - Contain 4 words/phrases like "Physicist", "Software Developer", "Educator", "Machinist"
            - Work together as a cohesive professional identity
            - Be distinct from other sets

            \(instructions.isEmpty ? "" : "User guidance: \(instructions)")

            Return JSON:
            {
                "sets": [
                    {"words": ["word1", "word2", "word3", "word4"]},
                    {"words": ["word1", "word2", "word3", "word4"]}
                ]
            }
            """

        do {
            let response: BulkTitleResponse = try await facade.executeStructuredWithDictionarySchema(
                prompt: prompt,
                modelId: getModelId(),
                as: BulkTitleResponse.self,
                schema: [
                    "type": "object",
                    "properties": [
                        "sets": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "words": ["type": "array", "items": ["type": "string"]]
                                ],
                                "required": ["words"],
                                "additionalProperties": false
                            ]
                        ]
                    ],
                    "required": ["sets"],
                    "additionalProperties": false
                ],
                schemaName: "bulk_titles"
            )

            // Save all generated sets
            for set in response.sets {
                let words = set.words.prefix(4).enumerated().map { index, text in
                    TitleWord(text: text, isLocked: false)
                }
                guard words.count == 4 else { continue }

                let titleSet = TitleSetRecord(
                    words: Array(words),
                    notes: "Bulk generated"
                )
                store.add(titleSet)
            }

        } catch {
            Logger.error("Bulk title generation failed: \(error)", category: .ai)
            aiComment = "Bulk generation failed. Please try again."
        }
    }

    private func buildHistoryContext() -> String {
        guard !conversationHistory.isEmpty else { return "" }

        var context = "Previous generation history:\n"
        for (index, turn) in conversationHistory.suffix(5).enumerated() {
            context += "\nTurn \(index + 1):\n"
            if !turn.lockedWordTexts.isEmpty {
                context += "- Locked: \(turn.lockedWordTexts.joined(separator: ", "))\n"
            }
            if let instructions = turn.userInstructions {
                context += "- Instructions: \(instructions)\n"
            }
            context += "- Generated: \(turn.generatedWords.joined(separator: ", "))\n"
            if let comment = turn.aiComment {
                context += "- AI comment: \(comment)\n"
            }
        }
        return context
    }

    private func getModelId() -> String {
        // Use configured model or fallback
        UserDefaults.standard.string(forKey: "onboardingModel") ?? "anthropic/claude-sonnet-4"
    }
}

// MARK: - Word Slot View

private struct WordSlotView: View {
    @Binding var word: TitleWord
    let index: Int

    var body: some View {
        HStack {
            TextField("Word \(index + 1)", text: $word.text)
                .textFieldStyle(.plain)
                .font(.body)

            Button {
                word.isLocked.toggle()
            } label: {
                Image(systemName: word.isLocked ? "lock.fill" : "lock.open")
                    .foregroundStyle(word.isLocked ? .cyan : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(word.isLocked ? Color.cyan.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Title Set Row

private struct TitleSetBrowserRow: View {
    let titleSet: TitleSetRecord
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onLoad: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleSet.compactDisplayString)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            if let notes = titleSet.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Text(titleSet.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if isHovering {
                    Button(action: onLoad) {
                        Image(systemName: "arrow.up.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Load into generator")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.cyan.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.cyan.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }
}

// MARK: - Response Types

private struct TitleGenerationResponse: Codable {
    let words: [String]
    let comment: String
}

private struct BulkTitleResponse: Codable {
    let sets: [BulkTitleSet]

    struct BulkTitleSet: Codable {
        let words: [String]
    }
}
