import Foundation
import SwiftyJSON
enum ExperienceDefaultsDecoder {
    static func draft(from json: JSON) -> ExperienceDefaultsDraft {
        var draft = ExperienceDefaultsDraft()
        let dictionary = json.dictionaryValue

        // Decode professional summary (non-array field)
        if let summary = dictionary["professional_summary"]?.string {
            draft.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        decodeCustomSection(from: dictionary["custom"], into: &draft)

        // Decode array-based sections
        for codec in ExperienceSectionCodecs.all {
            codec.decodeSection(from: dictionary[codec.key.rawValue], into: &draft)
        }
        return draft
    }

    private static func decodeCustomSection(from json: JSON?, into draft: inout ExperienceDefaultsDraft) {
        guard let customDict = json?.dictionary else { return }
        var fields: [CustomFieldValue] = []
        for (key, value) in customDict {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedKey.isEmpty == false else { continue }
            var values: [String] = []
            if let stringValue = value.string {
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false { values.append(trimmed) }
            } else if let array = value.arrayObject {
                values = array.compactMap { anyVal in
                    if let str = anyVal as? String {
                        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    }
                    if let num = anyVal as? NSNumber {
                        let str = num.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        return str.isEmpty ? nil : str
                    }
                    return nil
                }
            }
            guard values.isEmpty == false else { continue }
            fields.append(CustomFieldValue(key: trimmedKey, values: values))
        }
        if fields.isEmpty == false {
            draft.customFields = fields
            draft.isCustomEnabled = true
        }
    }
}
