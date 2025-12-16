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
    static func entryDrafts(from cards: [TimelineCard]) -> [TimelineEntryDraft] {
        cards.map { card in
            TimelineEntryDraft(
                id: card.id,
                experienceType: card.experienceType,
                title: card.title,
                organization: card.organization,
                location: card.location,
                start: card.start,
                end: card.end,
                summary: card.summary,
                highlights: card.highlights
            )
        }
    }

    static func cards(from drafts: [TimelineEntryDraft]) -> [TimelineCard] {
        drafts.map { draft in
            TimelineCard(
                id: draft.id,
                experienceType: draft.experienceType,
                title: draft.title,
                organization: draft.organization,
                location: draft.location,
                start: draft.start,
                end: draft.end,
                summary: draft.summary,
                highlights: draft.highlights
            )
        }
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
