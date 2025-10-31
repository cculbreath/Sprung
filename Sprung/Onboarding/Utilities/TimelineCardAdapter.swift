import Foundation
import SwiftyJSON

enum TimelineCardAdapter {
    static func cards(from timeline: JSON) -> (cards: [TimelineCard], meta: JSON?) {
        let experiences = timeline["experiences"].arrayValue
        var cards: [TimelineCard] = []

        for entry in experiences {
            if let card = TimelineCard(json: entry) {
                cards.append(card)
            } else {
                let synthesized = TimelineCard(id: UUID().uuidString, fields: entry)
                cards.append(synthesized)
            }
        }

        let meta: JSON?
        if timeline["meta"] != .null {
            meta = timeline["meta"]
        } else {
            meta = nil
        }

        return (cards, meta)
    }

    static func makeTimelineJSON(cards: [TimelineCard], meta: JSON?) -> JSON {
        var timeline = JSON()
        timeline["experiences"] = JSON(cards.map { $0.json })
        if let meta, meta != .null {
            timeline["meta"] = meta
        }
        return timeline
    }

    static func normalizedTimeline(_ input: JSON) -> JSON {
        let result = cards(from: input)
        return makeTimelineJSON(cards: result.cards, meta: result.meta)
    }
}
