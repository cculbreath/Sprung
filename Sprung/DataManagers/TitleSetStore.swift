//
//  TitleSetStore.swift
//  Sprung
//
//  SwiftData store for professional identity title sets.
//  Supports interactive generation with word locking and conversation history.
//

import Foundation
import Observation
import SwiftData

// MARK: - Model

@Model
final class TitleSetRecord {
    @Attribute(.unique) var id: UUID

    /// The 4 identity words (stored as JSON)
    var wordsJSON: String

    /// Optional user notes describing this combination
    var notes: String?

    /// Generation conversation history (stored as JSON)
    var historyJSON: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        words: [TitleWord] = [],
        notes: String? = nil,
        history: [GenerationTurn] = []
    ) {
        self.id = id
        self.wordsJSON = Self.encodeWords(words)
        self.notes = notes
        self.historyJSON = Self.encodeHistory(history)
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Computed Properties

    var words: [TitleWord] {
        get { Self.decodeWords(wordsJSON) }
        set { wordsJSON = Self.encodeWords(newValue) }
    }

    var history: [GenerationTurn] {
        get { Self.decodeHistory(historyJSON) }
        set { historyJSON = Self.encodeHistory(newValue) }
    }

    /// Display string: "Physicist. Developer. Educator. Machinist."
    var displayString: String {
        words.map { $0.text }.joined(separator: ". ") + "."
    }

    /// Compact display: "Physicist · Developer · Educator · Machinist"
    var compactDisplayString: String {
        words.map { $0.text }.joined(separator: " · ")
    }

    // MARK: - JSON Encoding/Decoding

    private static func encodeWords(_ words: [TitleWord]) -> String {
        guard let data = try? JSONEncoder().encode(words),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private static func decodeWords(_ json: String) -> [TitleWord] {
        guard let data = json.data(using: .utf8),
              let words = try? JSONDecoder().decode([TitleWord].self, from: data) else {
            return []
        }
        return words
    }

    private static func encodeHistory(_ history: [GenerationTurn]) -> String? {
        guard !history.isEmpty,
              let data = try? JSONEncoder().encode(history),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private static func decodeHistory(_ json: String?) -> [GenerationTurn] {
        guard let json = json,
              let data = json.data(using: .utf8),
              let history = try? JSONDecoder().decode([GenerationTurn].self, from: data) else {
            return []
        }
        return history
    }
}

// MARK: - Supporting Types

/// A single word in a title set with lock state
struct TitleWord: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var isLocked: Bool

    init(id: UUID = UUID(), text: String, isLocked: Bool = false) {
        self.id = id
        self.text = text
        self.isLocked = isLocked
    }
}

/// A single turn in the generation conversation
struct GenerationTurn: Codable, Identifiable {
    var id: UUID
    var timestamp: Date
    var userInstructions: String?
    var lockedWordTexts: [String]
    var generatedWords: [String]
    var aiComment: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        userInstructions: String? = nil,
        lockedWordTexts: [String] = [],
        generatedWords: [String] = [],
        aiComment: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.userInstructions = userInstructions
        self.lockedWordTexts = lockedWordTexts
        self.generatedWords = generatedWords
        self.aiComment = aiComment
    }
}

// MARK: - Store

@Observable
@MainActor
final class TitleSetStore: SwiftDataStore {
    let modelContext: ModelContext

    /// Cached title sets - stored property for @Observable tracking
    private(set) var allTitleSets: [TitleSetRecord] = []

    init(context: ModelContext) {
        self.modelContext = context
        refreshCache()
        Logger.info("TitleSetStore initialized", category: .data)
    }

    // MARK: - Cache Management

    private func refreshCache() {
        let descriptor = FetchDescriptor<TitleSetRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        allTitleSets = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Queries

    var titleSetCount: Int {
        allTitleSets.count
    }

    var hasTitleSets: Bool {
        titleSetCount > 0
    }

    func titleSet(for id: UUID) -> TitleSetRecord? {
        allTitleSets.first { $0.id == id }
    }

    // MARK: - CRUD

    func add(_ titleSet: TitleSetRecord) {
        modelContext.insert(titleSet)
        saveContext()
        refreshCache()
        Logger.info("Added title set: \(titleSet.compactDisplayString)", category: .data)
    }

    func update(_ titleSet: TitleSetRecord) {
        titleSet.updatedAt = Date()
        saveContext()
        refreshCache()
        Logger.info("Updated title set: \(titleSet.compactDisplayString)", category: .data)
    }

    func delete(_ titleSet: TitleSetRecord) {
        modelContext.delete(titleSet)
        saveContext()
        refreshCache()
        Logger.info("Deleted title set", category: .data)
    }

    func deleteAll() {
        for titleSet in allTitleSets {
            modelContext.delete(titleSet)
        }
        saveContext()
        refreshCache()
        Logger.info("Deleted all title sets", category: .data)
    }

    // MARK: - Conversation History

    /// Add a generation turn to a title set's history
    func addGenerationTurn(to titleSet: TitleSetRecord, turn: GenerationTurn) {
        var history = titleSet.history
        history.append(turn)
        titleSet.history = history
        titleSet.updatedAt = Date()
        saveContext()
        refreshCache()
    }

    /// Build conversation context for LLM from history
    func buildConversationContext(for titleSet: TitleSetRecord) -> String {
        guard !titleSet.history.isEmpty else { return "" }

        var context = "## Previous Generation History\n\n"

        for (index, turn) in titleSet.history.enumerated() {
            context += "### Turn \(index + 1)\n"

            if !turn.lockedWordTexts.isEmpty {
                context += "Locked words: \(turn.lockedWordTexts.joined(separator: ", "))\n"
            }

            if let instructions = turn.userInstructions, !instructions.isEmpty {
                context += "User instructions: \(instructions)\n"
            }

            context += "Generated: \(turn.generatedWords.joined(separator: ", "))\n"

            if let comment = turn.aiComment, !comment.isEmpty {
                context += "AI comment: \(comment)\n"
            }

            context += "\n"
        }

        return context
    }
}
