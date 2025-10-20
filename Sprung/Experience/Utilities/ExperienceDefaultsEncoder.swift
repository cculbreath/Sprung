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

        return result
    }
}
