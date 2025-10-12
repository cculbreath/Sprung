import Foundation
import SwiftyJSON

@MainActor
final class OnboardingArtifactStore {
    private enum ArtifactFile: String {
        case applicantProfile = "applicant_profile.json"
        case defaultValues = "default_values.json"
        case knowledgeCards = "knowledge_cards.json"
        case skillIndex = "skills_index.json"
        case profileContext = "profile_context.txt"
        case needsVerification = "needs_verification.json"
    }

    private let fileManager: FileManager
    private let directory: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = FileHandler.artifactsDirectory()
    }

    func loadArtifacts() -> OnboardingArtifacts {
        let applicantProfile = readJSON(.applicantProfile)
        let defaultValues = readJSON(.defaultValues)
        let knowledgeCards = readJSON(.knowledgeCards)?.arrayValue ?? []
        let skillMap = readJSON(.skillIndex)
        let profileContext = readString(.profileContext)
        let needsVerification = readJSON(.needsVerification)?.arrayValue.compactMap { $0.string } ?? []

        return OnboardingArtifacts(
            applicantProfile: applicantProfile,
            defaultValues: defaultValues,
            knowledgeCards: knowledgeCards,
            skillMap: skillMap,
            profileContext: profileContext,
            needsVerification: needsVerification
        )
    }

    @discardableResult
    func mergeApplicantProfile(patch: JSON) -> JSON {
        let merged = merge(jsonAt: .applicantProfile, with: patch)
        writeJSON(merged, to: .applicantProfile)
        return merged
    }

    @discardableResult
    func mergeDefaultValues(patch: JSON) -> JSON {
        let merged = merge(jsonAt: .defaultValues, with: patch)
        writeJSON(merged, to: .defaultValues)
        return merged
    }

    @discardableResult
    func appendKnowledgeCards(_ cards: [JSON]) -> [JSON] {
        guard !cards.isEmpty else {
            return readJSON(.knowledgeCards)?.arrayValue ?? []
        }

        var existing = readJSON(.knowledgeCards)?.arrayValue ?? []
        var seenTitles = Set(existing.compactMap { $0["title"].string?.lowercased() })

        for card in cards {
            guard let title = card["title"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            let normalized = title.lowercased()
            if seenTitles.contains(normalized) { continue }
            existing.append(card)
            seenTitles.insert(normalized)
        }

        let json = JSON(existing)
        writeJSON(json, to: .knowledgeCards)
        return existing
    }

    @discardableResult
    func mergeSkillMap(patch: JSON) -> JSON {
        let merged = merge(jsonAt: .skillIndex, with: patch)
        writeJSON(merged, to: .skillIndex)
        return merged
    }

    func updateProfileContext(_ value: String) {
        writeString(value, to: .profileContext)
    }

    @discardableResult
    func appendNeedsVerification(_ values: [String]) -> [String] {
        guard !values.isEmpty else {
            return readJSON(.needsVerification)?.arrayValue.compactMap { $0.string } ?? []
        }

        var existing = Set(readJSON(.needsVerification)?.arrayValue.compactMap { $0.string } ?? [])
        for item in values {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                existing.insert(trimmed)
            }
        }
        let sorted = existing.sorted()
        writeJSON(JSON(sorted), to: .needsVerification)
        return sorted
    }

    // MARK: - Private Helpers

    private func merge(jsonAt file: ArtifactFile, with patch: JSON) -> JSON {
        guard patch != .null else {
            return readJSON(file) ?? JSON()
        }

        let base = readJSON(file) ?? JSON()
        if base.type == .null {
            return patch
        }
        return mergeJSON(base: base, patch: patch)
    }

    private func readJSON(_ file: ArtifactFile) -> JSON? {
        let url = directory.appendingPathComponent(file.rawValue)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let jsonObject = try JSON(data: data)
            return jsonObject
        } catch {
            Logger.error("Failed to read JSON artifact at \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func writeJSON(_ json: JSON, to file: ArtifactFile) {
        let url = directory.appendingPathComponent(file.rawValue)
        do {
            let data = try json.rawData(options: [.prettyPrinted])
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.error("Failed to write JSON artifact at \(url.lastPathComponent): \(error)")
        }
    }

    private func readString(_ file: ArtifactFile) -> String? {
        let url = directory.appendingPathComponent(file.rawValue)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func writeString(_ string: String, to file: ArtifactFile) {
        let url = directory.appendingPathComponent(file.rawValue)
        do {
            try string.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Logger.error("Failed to write text artifact at \(url.lastPathComponent): \(error)")
        }
    }

    private func mergeJSON(base: JSON, patch: JSON) -> JSON {
        if base.type == .null {
            return patch
        }
        var result = base
        for (key, subpatch):(String, JSON) in patch {
            switch subpatch.type {
            case .dictionary:
                let baseValue = result[key]
                result[key] = mergeJSON(base: baseValue, patch: subpatch)
            case .array:
                result[key] = subpatch
            default:
                result[key] = subpatch
            }
        }
        return result
    }
}
