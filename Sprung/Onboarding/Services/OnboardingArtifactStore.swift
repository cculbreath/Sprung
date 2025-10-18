import Foundation
import SwiftyJSON
import SwiftData

@MainActor
final class OnboardingArtifactStore: SwiftDataStore {
    private enum Constants {
        static let fetchDescriptor = FetchDescriptor<OnboardingArtifactRecord>()
    }

    let modelContext: ModelContext
    private var cachedRecord: OnboardingArtifactRecord?

    init(context: ModelContext) {
        self.modelContext = context
    }

    func loadArtifacts() -> OnboardingArtifacts {
        let record = ensureRecord()

        return OnboardingArtifacts(
            applicantProfile: decodeJSON(from: record.applicantProfileData),
            defaultValues: decodeJSON(from: record.defaultValuesData),
            knowledgeCards: decodeJSONArray(from: record.knowledgeCardsData),
            skillMap: decodeJSON(from: record.skillMapData),
            factLedger: decodeJSONArray(from: record.factLedgerData),
            styleProfile: decodeJSON(from: record.styleProfileData),
            writingSamples: decodeJSONArray(from: record.writingSamplesData),
            profileContext: record.profileContext,
            needsVerification: record.needsVerification
        )
    }

    @discardableResult
    func mergeApplicantProfile(patch: JSON) -> JSON {
        let record = ensureRecord()
        let merged = mergeJSONData(&record.applicantProfileData, patch: patch)
        touch(record)
        saveContext()
        return merged
    }

    @discardableResult
    func mergeDefaultValues(patch: JSON) -> JSON {
        let record = ensureRecord()
        let merged = mergeJSONData(&record.defaultValuesData, patch: patch)
        touch(record)
        saveContext()
        return merged
    }

    @discardableResult
    func appendKnowledgeCards(_ cards: [JSON]) -> [JSON] {
        guard !cards.isEmpty else {
            return decodeJSONArray(from: ensureRecord().knowledgeCardsData)
        }

        let record = ensureRecord()
        var existing = decodeJSONArray(from: record.knowledgeCardsData)
        var seenTitles = Set(existing.compactMap { $0["title"].string?.lowercased() })

        for card in cards where card.type == .dictionary {
            guard let title = card["title"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            let normalized = title.lowercased()
            if seenTitles.contains(normalized) { continue }
            existing.append(card)
            seenTitles.insert(normalized)
        }

        record.knowledgeCardsData = encodeJSONArray(existing)
        touch(record)
        saveContext()
        return existing
    }

    @discardableResult
    func mergeSkillMap(patch: JSON) -> JSON {
        let record = ensureRecord()
        let merged = mergeJSONData(&record.skillMapData, patch: patch)
        touch(record)
        saveContext()
        return merged
    }

    func updateProfileContext(_ value: String) {
        let record = ensureRecord()
        record.profileContext = value
        touch(record)
        saveContext()
    }

    @discardableResult
    func appendNeedsVerification(_ values: [String]) -> [String] {
        let record = ensureRecord()
        guard !values.isEmpty else {
            return record.needsVerification
        }

        var existing = Set(record.needsVerification)
        for item in values {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                existing.insert(trimmed)
            }
        }
        let sorted = existing.sorted()
        record.needsVerification = sorted
        touch(record)
        saveContext()
        return sorted
    }

    @discardableResult
    func appendFactLedgerEntries(_ entries: [JSON]) -> [JSON] {
        guard !entries.isEmpty else {
            return decodeJSONArray(from: ensureRecord().factLedgerData)
        }

        let record = ensureRecord()
        var existing = decodeJSONArray(from: record.factLedgerData)
        var seen = Set(existing.compactMap { normalizedIdentifier(for: $0, preferredKeys: ["id", "claim_id", "statement", "title"]) })

        for entry in entries where entry.type == .dictionary {
            if let identifier = normalizedIdentifier(for: entry, preferredKeys: ["id", "claim_id", "statement", "title"]) {
                if seen.contains(identifier) { continue }
                seen.insert(identifier)
            }
            existing.append(entry)
        }

        record.factLedgerData = encodeJSONArray(existing)
        touch(record)
        saveContext()
        return existing
    }

    func saveStyleProfile(_ profile: JSON?) {
        let record = ensureRecord()
        if let profile, profile.type != .null {
            record.styleProfileData = encodeJSON(profile)
        } else {
            record.styleProfileData = nil
        }
        touch(record)
        saveContext()
    }

    @discardableResult
    func saveWritingSamples(_ samples: [JSON]) -> [JSON] {
        let record = ensureRecord()
        guard !samples.isEmpty else {
            record.writingSamplesData = nil
            touch(record)
            saveContext()
            return []
        }

        var existing = decodeJSONArray(from: record.writingSamplesData)
        var seen = Set(existing.compactMap { normalizedIdentifier(for: $0, preferredKeys: ["id", "sample_id"]) })

        for sample in samples where sample.type == .dictionary {
            if let identifier = normalizedIdentifier(for: sample, preferredKeys: ["id", "sample_id"]) {
                if let index = existing.firstIndex(where: {
                    normalizedIdentifier(for: $0, preferredKeys: ["id", "sample_id"]) == identifier
                }) {
                    existing[index] = mergeJSON(base: existing[index], patch: sample)
                    continue
                }
                if seen.contains(identifier) { continue }
                seen.insert(identifier)
            }
            existing.append(sample)
        }

        record.writingSamplesData = encodeJSONArray(existing)
        touch(record)
        saveContext()
        return existing
    }

    // MARK: - Conversation State

    func loadConversationState() -> OpenAIConversationState? {
        guard let data = ensureRecord().conversationStateData else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(OpenAIConversationState.self, from: data)
    }

    func saveConversationState(_ state: OpenAIConversationState) {
        let record = ensureRecord()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        record.conversationStateData = try? encoder.encode(state)
        touch(record)
        saveContext()
    }

    func clearConversationState() {
        let record = ensureRecord()
        record.conversationStateData = nil
        touch(record)
        saveContext()
    }

    // MARK: - Helpers

    private func ensureRecord() -> OnboardingArtifactRecord {
        if let cachedRecord {
            return cachedRecord
        }

        if let existing = try? modelContext.fetch(Constants.fetchDescriptor).first {
            cachedRecord = existing
            return existing
        }

        let record = OnboardingArtifactRecord()
        modelContext.insert(record)
        cachedRecord = record
        saveContext()
        return record
    }

    private func mergeJSONData(_ data: inout Data?, patch: JSON) -> JSON {
        guard patch != .null else {
            return decodeJSON(from: data) ?? JSON()
        }

        let base = decodeJSON(from: data) ?? JSON()
        let merged: JSON
        if base.type == .null {
            merged = patch
        } else {
            merged = mergeJSON(base: base, patch: patch)
        }
        data = encodeJSON(merged)
        return merged
    }

    private func decodeJSON(from data: Data?) -> JSON? {
        guard let data else { return nil }
        return try? JSON(data: data)
    }

    private func decodeJSONArray(from data: Data?) -> [JSON] {
        guard let json = decodeJSON(from: data), json.type == .array else { return [] }
        return json.arrayValue
    }

    private func encodeJSON(_ json: JSON?) -> Data? {
        guard let json, json.type != .null else { return nil }
        return try? json.rawData()
    }

    private func encodeJSONArray(_ array: [JSON]) -> Data? {
        guard !array.isEmpty else { return nil }
        return try? JSON(array).rawData()
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

    private func normalizedIdentifier(for json: JSON, preferredKeys: [String]) -> String? {
        for key in preferredKeys {
            if let value = json[key].string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value.lowercased()
            }
        }
        return nil
    }

    private func touch(_ record: OnboardingArtifactRecord) {
        record.updatedAt = Date()
    }
}
