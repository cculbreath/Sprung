import Foundation
import Observation

@MainActor
@Observable
final class CareerKeywordStore {
    private(set) var keywords: [String] = []

    private let fileManager = FileManager.default
    private let appSupportDirectory: URL
    private let keywordsFileURL: URL

    init() {
        let baseSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let appDirectory = baseSupport.appendingPathComponent("Sprung", isDirectory: true)
        appSupportDirectory = appDirectory
        keywordsFileURL = appDirectory.appendingPathComponent("career_keywords.json", isDirectory: false)
        prepareStorage()
        loadKeywords()
    }

    func suggestions(
        matching query: String,
        excluding existing: Set<String>,
        limit: Int = 12
    ) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else { return [] }

        let lowercasedQuery = trimmedQuery.lowercased()
        var results: [String] = []

        for keyword in keywords {
            let normalized = keyword.lowercased()
            if normalized.hasPrefix(lowercasedQuery) || normalized.contains(lowercasedQuery) {
                if existing.contains(normalized) == false {
                    results.append(keyword)
                }
            }
            if results.count >= limit {
                break
            }
        }

        return results
    }

    func registerKeyword(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        if keywords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return
        }

        keywords.append(trimmed)
        keywords.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        persistKeywords()
    }

    // MARK: - Private Helpers

    private func prepareStorage() {
        if fileManager.fileExists(atPath: keywordsFileURL.path) {
            return
        }

        do {
            try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.warning("CareerKeywordStore: Failed to create Application Support directory: \(error)")
        }

        if let bundledURL = Bundle.main.url(forResource: "DefaultCareerKeywords", withExtension: "json") {
            do {
                try fileManager.copyItem(at: bundledURL, to: keywordsFileURL)
            } catch {
                Logger.warning("CareerKeywordStore: Failed to copy bundled keyword list: \(error)")
            }
        } else {
            Logger.warning("CareerKeywordStore: Bundled keyword file missing; creating empty list.")
            try? Data("[]".utf8).write(to: keywordsFileURL)
        }
    }

    private func loadKeywords() {
        guard let data = try? Data(contentsOf: keywordsFileURL) else {
            keywords = []
            return
        }

        if let decoded = try? JSONDecoder().decode([String].self, from: data) {
            keywords = decoded.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } else {
            Logger.warning("CareerKeywordStore: Failed to decode keyword list; starting empty.")
            keywords = []
        }
    }

    private func persistKeywords() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(keywords)
            try data.write(to: keywordsFileURL, options: [.atomic])
        } catch {
            Logger.warning("CareerKeywordStore: Failed to persist keywords: \(error)")
        }
    }
}
