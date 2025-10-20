import Foundation
import SwiftyJSON

enum ExperienceDefaultsDecoder {
    static func draft(from json: JSON) -> ExperienceDefaultsDraft {
        var draft = ExperienceDefaultsDraft()
        let dictionary = json.dictionaryValue

        for codec in ExperienceSectionCodecs.all {
            codec.decodeSection(from: dictionary[codec.key.rawValue], into: &draft)
        }

        return draft
    }
}
