//
//  TitleSetsBrowserTab.swift
//  Sprung
//
//  Interactive Title Set Generator for the Resource Browser.
//  Allows users to generate, lock, and refine professional identity word combinations.
//

import SwiftUI
import SwiftOpenAI

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

    private func generateWords() async {
        guard let facade = llmFacade else { return }

        // Get model configuration
        let (modelId, backend) = getModelConfig()
        guard !modelId.isEmpty else {
            aiComment = "No model configured. Please set the Seed Generation model in Settings."
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        // Build context from candidate's experience
        let experienceContext = buildExperienceContext()

        // Build context from conversation history
        let historyContext = buildHistoryContext()

        // Build context from approved combinations to avoid duplicates
        let approvedContext = buildApprovedContext()

        // Build locked words list
        let lockedWords = currentWords.enumerated()
            .filter { $0.element.isLocked }
            .map { (index: $0.offset, word: $0.element.text) }

        let lockedDescription = lockedWords.isEmpty
            ? "No words are locked."
            : "Locked words (must include these): " + lockedWords.map { $0.word }.joined(separator: ", ")

        let prompt = """
            Generate professional identity words for a resume title line.

            \(experienceContext)

            \(approvedContext)

            \(historyContext)

            Current state:
            \(lockedDescription)

            \(instructions.isEmpty ? "" : "User instructions: \(instructions)")

            Generate \(4 - lockedWords.count) new professional identity words to complement the locked words.
            These should be single words or short phrases like "Physicist", "Software Developer", "Educator", "Machinist".
            They should work together as a cohesive professional identity.
            IMPORTANT: Create a DISTINCT combination that differs meaningfully from the approved sets listed above.

            Arrange all 4 words (locked + new) in the best order for flow and impact.

            Return JSON:
            {
                "words": ["word1", "word2", "word3", "word4"],
                "comment": "Brief suggestion or observation about this combination"
            }

            Include all 4 words in the response, including the locked words in any position.
            """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "words": ["type": "array", "items": ["type": "string"]],
                "comment": ["type": "string"]
            ],
            "required": ["words", "comment"],
            "additionalProperties": false
        ]

        do {
            let response: TitleGenerationResponse
            if backend == .anthropic {
                // Use Anthropic-native structured output (requires beta header, auto-handled by SwiftOpenAI)
                let systemBlock = SwiftOpenAI.AnthropicSystemBlock(
                    text: "You are a professional identity consultant helping craft compelling resume title lines."
                )
                response = try await facade.executeStructuredWithAnthropicCaching(
                    systemContent: [systemBlock],
                    userPrompt: prompt,
                    modelId: modelId,
                    responseType: TitleGenerationResponse.self,
                    schema: schema
                )
            } else {
                // Use OpenRouter structured output
                response = try await facade.executeStructuredWithDictionarySchema(
                    prompt: prompt,
                    modelId: modelId,
                    as: TitleGenerationResponse.self,
                    schema: schema,
                    schemaName: "title_generation",
                    backend: backend
                )
            }

            // Update words - preserve locked state for words that were locked
            let lockedTexts = Set(lockedWords.map { $0.word })
            for (index, word) in response.words.prefix(4).enumerated() {
                currentWords[index].text = word
                currentWords[index].isLocked = lockedTexts.contains(word)
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
        guard let facade = llmFacade else { return }

        // Get model configuration
        let (modelId, backend) = getModelConfig()
        guard !modelId.isEmpty else {
            aiComment = "No model configured. Please set the Seed Generation model in Settings."
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        // Build context from candidate's experience
        let experienceContext = buildExperienceContext()

        // Build context from approved combinations to avoid duplicates
        let approvedContext = buildApprovedContext()

        // Get locked words
        let lockedWords = currentWords.filter { $0.isLocked && !$0.text.isEmpty }
        let lockedTexts = lockedWords.map { $0.text }
        let wordsToGenerate = 4 - lockedTexts.count

        let lockedInstruction: String
        if lockedTexts.isEmpty {
            lockedInstruction = ""
        } else {
            lockedInstruction = """
                LOCKED WORDS REQUIREMENT:
                Each set MUST include: \(lockedTexts.joined(separator: ", "))
                Place locked words in ANY position (not always first) - vary the order for natural flow.
                Generate \(wordsToGenerate) additional words to complement the locked words.
                """
        }

        let prompt = """
            Generate \(count) distinct sets of 4 professional identity words for resume title lines.

            \(experienceContext)

            \(approvedContext)

            \(lockedInstruction)

            Each set should:
            - Contain exactly 4 words/phrases like "Physicist", "Software Developer", "Educator", "Machinist"
            - Arrange words in the best order for flow and impact (locked words can go anywhere)
            - Work together as a cohesive professional identity
            - Be distinct from other sets AND from the already approved sets listed above
            - Accurately reflect the candidate's actual background shown above

            \(instructions.isEmpty ? "" : "User guidance: \(instructions)")

            Return JSON:
            {
                "sets": [
                    {"words": ["word1", "word2", "word3", "word4"]},
                    {"words": ["word1", "word2", "word3", "word4"]}
                ]
            }
            """

        let schema: [String: Any] = [
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
        ]

        do {
            let response: BulkTitleResponse
            if backend == .anthropic {
                // Use Anthropic-native structured output
                let systemBlock = SwiftOpenAI.AnthropicSystemBlock(
                    text: "You are a professional identity consultant helping craft compelling resume title lines."
                )
                response = try await facade.executeStructuredWithAnthropicCaching(
                    systemContent: [systemBlock],
                    userPrompt: prompt,
                    modelId: modelId,
                    responseType: BulkTitleResponse.self,
                    schema: schema
                )
            } else {
                // Use OpenRouter structured output
                response = try await facade.executeStructuredWithDictionarySchema(
                    prompt: prompt,
                    modelId: modelId,
                    as: BulkTitleResponse.self,
                    schema: schema,
                    schemaName: "bulk_titles",
                    backend: backend
                )
            }

            // Add generated sets to pending list for user review
            let lockedTextSet = Set(lockedTexts)
            for set in response.sets {
                let words = set.words.prefix(4).map { text in
                    // Mark words that match locked words as locked
                    TitleWord(text: text, isLocked: lockedTextSet.contains(text))
                }
                guard words.count == 4 else { continue }
                pendingSets.append(Array(words))
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

    private func buildApprovedContext() -> String {
        guard let store = titleSetStore, !store.allTitleSets.isEmpty else { return "" }

        var context = "Already approved title sets (DO NOT duplicate these):\n"
        for titleSet in store.allTitleSets {
            let wordsDisplay = titleSet.words.map { $0.text }.joined(separator: " · ")
            context += "- \(wordsDisplay)\n"
        }
        return context
    }

    private func buildExperienceContext() -> String {
        guard !skills.isEmpty else { return "" }

        var context = "## Candidate's Professional Background\n\n"
        context += "### Skills\n"
        let skillNames = skills.map { $0.canonical }
        context += skillNames.joined(separator: ", ")
        context += "\n\n"

        context += """
            Based on this skill set, generate professional identity words that accurately
            represent this candidate's actual expertise and specializations.
            Do NOT invent credentials or expertise areas not supported by the skills above.
            """

        return context
    }

    private func getModelConfig() -> (modelId: String, backend: LLMFacade.Backend) {
        let backendString = UserDefaults.standard.string(forKey: "seedGenerationBackend") ?? "anthropic"
        let modelKey = backendString == "anthropic" ? "seedGenerationAnthropicModelId" : "seedGenerationOpenRouterModelId"
        let modelId = UserDefaults.standard.string(forKey: modelKey) ?? ""

        let backend: LLMFacade.Backend
        switch backendString {
        case "anthropic":
            backend = .anthropic
        case "openrouter":
            backend = .openRouter
        default:
            backend = .anthropic
        }

        return (modelId, backend)
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

// MARK: - Pending Title Set Row

private struct PendingTitleSetRow: View {
    let words: [TitleWord]
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Words display - wrapping allowed
            Text(words.map { $0.text }.joined(separator: " · "))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons
            HStack(spacing: 12) {
                Spacer()

                Button(action: onReject) {
                    Label("Reject", systemImage: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
