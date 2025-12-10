import Foundation
enum ExperienceDefaultsEncoder {
    static func makeSeedDictionary(from defaults: ExperienceDefaults) -> [String: Any] {
        let draft = ExperienceDefaultsDraft(model: defaults)
        return makeSeedDictionary(from: draft)
    }
    static func makeSeedDictionary(from draft: ExperienceDefaultsDraft) -> [String: Any] {
        var result: [String: Any] = [:]
        for codec in ExperienceSectionCodecs.all {
            guard let items = codec.encodeSection(from: draft) else { continue }
            result[codec.key.rawValue] = items
        }
        let customPayload = customSection(from: draft)
        if customPayload.isEmpty == false {
            result["custom"] = customPayload
        }
        return result
    }
}
private extension ExperienceDefaultsEncoder {
    static func customSection(from draft: ExperienceDefaultsDraft) -> [String: Any] {
        guard draft.isCustomEnabled else { return [:] }
        var payload: [String: Any] = [:]
        for field in draft.customFields {
            let trimmedKey = field.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedKey.isEmpty == false else { continue }
            let cleanedValues = field.values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            guard cleanedValues.isEmpty == false else { continue }
            payload[trimmedKey] = cleanedValues
        }
        return payload
    }
}
