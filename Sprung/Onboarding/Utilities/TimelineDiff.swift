import Foundation
struct TimelineDiff {
    struct FieldChange {
        let field: String
    }
    struct HighlightChange {
        let added: [String]
        let removed: [String]
        var isEmpty: Bool {
            added.isEmpty && removed.isEmpty
        }
    }
    struct CardChange {
        let title: String
        let fieldChanges: [FieldChange]
        let highlightChange: HighlightChange?
        var isEmpty: Bool {
            fieldChanges.isEmpty && (highlightChange?.isEmpty ?? true)
        }
    }
    var added: [TimelineCard]
    var removed: [TimelineCard]
    var updated: [CardChange]
    var reordered: Bool
    var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && updated.isEmpty && reordered == false
    }
}
enum TimelineDiffBuilder {
    static func diff(original: [TimelineCard], updated: [TimelineCard]) -> TimelineDiff {
        let originalById = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0) })
        let updatedById = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
        let added = updated.filter { originalById[$0.id] == nil }
        let removed = original.filter { updatedById[$0.id] == nil }
        var cardChanges: [TimelineDiff.CardChange] = []
        for (identifier, originalCard) in originalById {
            guard let updatedCard = updatedById[identifier] else { continue }
            let fieldChanges = collectFieldChanges(old: originalCard, new: updatedCard)
            let highlightChange = collectHighlightChange(old: originalCard.highlights, new: updatedCard.highlights)
            let change = TimelineDiff.CardChange(
                title: bestTitle(for: updatedCard, fallback: originalCard),
                fieldChanges: fieldChanges,
                highlightChange: highlightChange
            )
            if change.isEmpty == false {
                cardChanges.append(change)
            }
        }
        let reordered = didReorder(original: original, updated: updated)
        return TimelineDiff(
            added: added,
            removed: removed,
            updated: cardChanges,
            reordered: reordered
        )
    }
    private static func collectFieldChanges(old: TimelineCard, new: TimelineCard) -> [TimelineDiff.FieldChange] {
        var changes: [TimelineDiff.FieldChange] = []
        compareField("experienceType", old: old.experienceType.rawValue, new: new.experienceType.rawValue, changes: &changes)
        compareField("title", old: old.title, new: new.title, changes: &changes)
        compareField("organization", old: old.organization, new: new.organization, changes: &changes)
        compareField("location", old: old.location, new: new.location, changes: &changes)
        compareField("start", old: old.start, new: new.start, changes: &changes)
        compareField("end", old: old.end, new: new.end, changes: &changes)
        compareField("summary", old: old.summary, new: new.summary, changes: &changes)
        return changes
    }
    private static func collectHighlightChange(old: [String], new: [String]) -> TimelineDiff.HighlightChange? {
        guard old != new else { return nil }
        let oldSet = Set(old.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let newSet = Set(new.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let added = newSet.subtracting(oldSet)
        let removed = oldSet.subtracting(newSet)
        return TimelineDiff.HighlightChange(
            added: Array(added),
            removed: Array(removed)
        )
    }
    private static func compareField(
        _ name: String,
        old: String,
        new: String,
        changes: inout [TimelineDiff.FieldChange]
    ) {
        if old != new {
            changes.append(
                TimelineDiff.FieldChange(
                    field: name
                )
            )
        }
    }
    private static func didReorder(original: [TimelineCard], updated: [TimelineCard]) -> Bool {
        let originalIds = original.map { $0.id }
        let updatedIds = updated.map { $0.id }
        guard originalIds.count == updatedIds.count else {
            // additions or removals already accounted separately; treat as reorder only when counts match
            let sharedOriginal = originalIds.filter { updatedIds.contains($0) }
            let sharedUpdated = updatedIds.filter { originalIds.contains($0) }
            return sharedOriginal != sharedUpdated
        }
        return originalIds != updatedIds
    }
    private static func bestTitle(for card: TimelineCard, fallback: TimelineCard) -> String {
        func summary(from card: TimelineCard) -> String {
            if !card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return card.title
            }
            if !card.organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return card.organization
            }
            return "Card \(card.id)"
        }
        let preferred = summary(from: card)
        if preferred.starts(with: "Card ") {
            return summary(from: fallback)
        }
        return preferred
    }
}
