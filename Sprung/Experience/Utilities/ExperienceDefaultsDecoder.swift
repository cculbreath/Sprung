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

        // Decode array-based sections
        for codec in ExperienceSectionCodecs.all {
            codec.decodeSection(from: dictionary[codec.key.rawValue], into: &draft)
        }
        return draft
    }
}
