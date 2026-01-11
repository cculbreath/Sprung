import Foundation
import SwiftyJSON

/// Manages an ephemeral filesystem workspace for agentic card merging.
/// Creates a fresh workspace for each dedupe run, handles export/import, and cleanup.
@MainActor
final class CardMergeWorkspaceService {

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    /// Workspace directory path
    private var workspacePath: URL?

    /// Path to the cards subdirectory
    private var cardsPath: URL? {
        workspacePath?.appendingPathComponent("cards")
    }

    /// Path to the index file
    private var indexPath: URL? {
        workspacePath?.appendingPathComponent("index.json")
    }

    // MARK: - Workspace Lifecycle

    /// Creates a fresh workspace directory, removing any existing one.
    /// Returns the workspace path.
    func createWorkspace() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sprungDir = appSupport.appendingPathComponent("Sprung")
        let workspace = sprungDir.appendingPathComponent("merge-workspace")

        // Remove existing workspace if present
        if FileManager.default.fileExists(atPath: workspace.path) {
            try FileManager.default.removeItem(at: workspace)
            Logger.info("🗑️ Removed existing merge workspace", category: .ai)
        }

        // Create fresh workspace and cards subdirectory
        let cards = workspace.appendingPathComponent("cards")
        try FileManager.default.createDirectory(at: cards, withIntermediateDirectories: true)

        workspacePath = workspace
        Logger.info("📁 Created merge workspace at \(workspace.path)", category: .ai)

        return workspace
    }

    /// Deletes the workspace directory and all contents.
    func deleteWorkspace() throws {
        guard let workspace = workspacePath else { return }

        if FileManager.default.fileExists(atPath: workspace.path) {
            try FileManager.default.removeItem(at: workspace)
            Logger.info("🗑️ Deleted merge workspace", category: .ai)
        }

        workspacePath = nil
    }

    // MARK: - Export

    /// Exports cards to the workspace as individual JSON files plus an index.
    func exportCards(_ cards: [KnowledgeCard]) throws {
        guard let cardsDir = cardsPath, let indexFile = indexPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        var indexEntries: [[String: Any]] = []

        for card in cards {
            // Write full card to {uuid}.json
            let cardFile = cardsDir.appendingPathComponent("\(card.id.uuidString).json")
            let cardData = try encoder.encode(card)
            try cardData.write(to: cardFile)

            // Add summary to index
            let summary: [String: Any] = [
                "id": card.id.uuidString,
                "cardType": card.cardType?.rawValue ?? "other",
                "title": card.title,
                "organization": card.organization ?? "",
                "dateRange": card.dateRange ?? "",
                "narrative_preview": String(card.narrative.prefix(200))
            ]
            indexEntries.append(summary)
        }

        // Write index file
        let indexData = try JSONSerialization.data(withJSONObject: indexEntries, options: [.prettyPrinted, .sortedKeys])
        try indexData.write(to: indexFile)

        Logger.info("📤 Exported \(cards.count) cards to workspace", category: .ai)
    }

    // MARK: - Agent Tools

    /// Lists all cards in the workspace (returns index content).
    func listCards() throws -> JSON {
        guard let indexFile = indexPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let data = try Data(contentsOf: indexFile)
        return try JSON(data: data)
    }

    /// Reads a single card by ID.
    func readCard(id: String) throws -> JSON {
        guard let cardsDir = cardsPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let cardFile = cardsDir.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: cardFile.path) else {
            throw WorkspaceError.cardNotFound(id)
        }

        let data = try Data(contentsOf: cardFile)
        return try JSON(data: data)
    }

    /// Writes a merged card to the workspace.
    /// Also updates the index with the new card's summary.
    func writeMergedCard(_ cardJSON: JSON) throws {
        guard let cardsDir = cardsPath, let indexFile = indexPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let cardId = cardJSON["id"].stringValue
        guard !cardId.isEmpty else {
            throw WorkspaceError.invalidCard("Missing card ID")
        }

        // Write the card file
        let cardFile = cardsDir.appendingPathComponent("\(cardId).json")
        let cardData = try cardJSON.rawData(options: [.prettyPrinted, .sortedKeys])
        try cardData.write(to: cardFile)

        // Update index - add the new card's summary
        var index = try listCards().arrayValue
        let summary: [String: Any] = [
            "id": cardId,
            "cardType": cardJSON["cardType"].stringValue,
            "title": cardJSON["title"].stringValue,
            "organization": cardJSON["organization"].stringValue,
            "dateRange": cardJSON["dateRange"].stringValue,
            "narrative_preview": String(cardJSON["narrative"].stringValue.prefix(200))
        ]
        index.append(JSON(summary))

        let indexJSON = JSON(index)
        let indexData = try indexJSON.rawData(options: [.prettyPrinted, .sortedKeys])
        try indexData.write(to: indexFile)

        Logger.info("✍️ Wrote merged card: \(cardId)", category: .ai)
    }

    /// Deletes a card from the workspace.
    /// Also removes it from the index.
    func deleteCard(id: String) throws {
        guard let cardsDir = cardsPath, let indexFile = indexPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        // Delete the card file
        let cardFile = cardsDir.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: cardFile.path) {
            try FileManager.default.removeItem(at: cardFile)
        }

        // Update index - remove the deleted card
        var index = try listCards().arrayValue
        index.removeAll { $0["id"].stringValue == id }

        let indexJSON = JSON(index)
        let indexData = try indexJSON.rawData(options: [.prettyPrinted, .sortedKeys])
        try indexData.write(to: indexFile)

        Logger.info("🗑️ Deleted card: \(id)", category: .ai)
    }

    // MARK: - Import

    /// Imports all remaining cards from the workspace as KnowledgeCard objects.
    func importCards() throws -> [KnowledgeCard] {
        guard let cardsDir = cardsPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: cardsDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        var cards: [KnowledgeCard] = []

        for fileURL in fileURLs {
            do {
                let data = try Data(contentsOf: fileURL)
                let card = try decoder.decode(KnowledgeCard.self, from: data)
                cards.append(card)
            } catch {
                Logger.warning("⚠️ Failed to parse card from \(fileURL.lastPathComponent): \(error.localizedDescription)", category: .ai)
            }
        }

        Logger.info("📥 Imported \(cards.count) cards from workspace", category: .ai)
        return cards
    }

    /// Returns the count of cards currently in the workspace.
    func cardCount() throws -> Int {
        guard let cardsDir = cardsPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: cardsDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        return fileURLs.count
    }

    // MARK: - Errors

    enum WorkspaceError: Error, LocalizedError {
        case workspaceNotCreated
        case cardNotFound(String)
        case invalidCard(String)

        var errorDescription: String? {
            switch self {
            case .workspaceNotCreated:
                return "Workspace has not been created"
            case .cardNotFound(let id):
                return "Card not found: \(id)"
            case .invalidCard(let reason):
                return "Invalid card: \(reason)"
            }
        }
    }
}
