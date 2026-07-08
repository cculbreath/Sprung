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
