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

    static func workDrafts(from cards: [TimelineCard]) -> [WorkExperienceDraft] {
        cards.map { card in
            var draft = WorkExperienceDraft()
            draft.id = UUID(uuidString: card.id) ?? UUID()
            draft.position = card.title
            draft.name = card.organization
            draft.location = card.location
            draft.startDate = card.start
            draft.endDate = card.end
            draft.summary = card.summary
            draft.highlights = card.highlights.map { text in
                var highlight = HighlightDraft()
                highlight.text = text
                return highlight
            }
            return draft
        }
    }

    static func cards(from drafts: [WorkExperienceDraft]) -> [TimelineCard] {
        drafts.map { draft in
            TimelineCard(
                id: draft.id.uuidString,
                title: draft.position,
                organization: draft.name,
                location: draft.location,
                start: draft.startDate,
                end: draft.endDate,
                summary: draft.summary,
                highlights: draft.highlights.map { $0.text }
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
