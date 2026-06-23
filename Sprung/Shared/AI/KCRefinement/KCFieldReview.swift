import Foundation

/// A single editable knowledge-card field, identified by the JSON key the
/// refinement schema uses for it. Drives the field-by-field review diff: reading
/// before/after values, detecting changes, applying an accepted value, and
/// decoding a single-field retry response.
enum KCField: String, CaseIterable, Identifiable {
    case title
    case narrative
    case cardType
    case dateRange
    case organization
    case location
    case domains
    case scale
    case keywords
    case technologies
    case outcomes
    case suggestedBullets
    case evidenceQuality
    case facts
    case verbatimExcerpts

    var id: String { rawValue }

    /// JSON property name in the refinement schema (identical to the raw value).
    var jsonKey: String { rawValue }

    var label: String {
        switch self {
        case .title: return "Title"
        case .narrative: return "Content"
        case .cardType: return "Card Type"
        case .dateRange: return "Time Period"
        case .organization: return "Organization"
        case .location: return "Location"
        case .domains: return "Domains"
        case .scale: return "Scale & Metrics"
        case .keywords: return "Keywords"
        case .technologies: return "Technologies"
        case .outcomes: return "Outcomes"
        case .suggestedBullets: return "Suggested Bullets"
        case .evidenceQuality: return "Evidence Quality"
        case .facts: return "Facts"
        case .verbatimExcerpts: return "Verbatim Excerpts"
        }
    }

    // MARK: - Reading values

    func before(from card: KnowledgeCard) -> KCFieldValue {
        switch self {
        case .title: return .text(card.title)
        case .narrative: return .text(card.narrative)
        case .cardType: return .optionalText(card.cardType?.rawValue)
        case .dateRange: return .optionalText(card.dateRange.nilIfBlank)
        case .organization: return .optionalText(card.organization.nilIfBlank)
        case .location: return .optionalText(card.location.nilIfBlank)
        case .evidenceQuality: return .optionalText(card.evidenceQuality.nilIfBlank)
        case .domains: return .list(card.extractable.domains)
        case .scale: return .list(card.extractable.scale)
        case .keywords: return .list(card.extractable.keywords)
        case .technologies: return .list(card.technologies)
        case .outcomes: return .list(card.outcomes)
        case .suggestedBullets: return .list(card.suggestedBullets)
        case .facts:
            return .facts(card.facts.map {
                RefinedFact(category: $0.category, statement: $0.statement, confidence: $0.confidence)
            })
        case .verbatimExcerpts:
            return .excerpts(card.verbatimExcerpts.map {
                RefinedExcerpt(context: $0.context, location: $0.location, text: $0.text, preservationReason: $0.preservationReason)
            })
        }
    }

    func after(from refined: RefinedKnowledgeCard) -> KCFieldValue {
        switch self {
        case .title: return .text(refined.title)
        case .narrative: return .text(refined.narrative)
        case .cardType: return .optionalText(refined.cardType.nilIfBlank)
        case .dateRange: return .optionalText(refined.dateRange.nilIfBlank)
        case .organization: return .optionalText(refined.organization.nilIfBlank)
        case .location: return .optionalText(refined.location.nilIfBlank)
        case .evidenceQuality: return .optionalText(refined.evidenceQuality.nilIfBlank)
        case .domains: return .list(refined.domains)
        case .scale: return .list(refined.scale)
        case .keywords: return .list(refined.keywords)
        case .technologies: return .list(refined.technologies)
        case .outcomes: return .list(refined.outcomes)
        case .suggestedBullets: return .list(refined.suggestedBullets)
        case .facts: return .facts(refined.facts ?? [])
        case .verbatimExcerpts: return .excerpts(refined.verbatimExcerpts ?? [])
        }
    }

    /// Decode this field's value from the raw JSON value returned by a single-field
    /// retry (the value under `jsonKey` in the response object).
    func value(fromJSON raw: Any?) -> KCFieldValue {
        switch self {
        case .title, .narrative:
            return .text((raw as? String) ?? "")
        case .cardType, .dateRange, .organization, .location, .evidenceQuality:
            return .optionalText((raw as? String).nilIfBlank)
        case .domains, .scale, .keywords, .technologies, .outcomes, .suggestedBullets:
            return .list((raw as? [Any])?.compactMap { $0 as? String } ?? [])
        case .facts:
            return .facts(decodeArray(raw, as: RefinedFact.self))
        case .verbatimExcerpts:
            return .excerpts(decodeArray(raw, as: RefinedExcerpt.self))
        }
    }

    // MARK: - Applying values

    /// Write an accepted value for this field onto the live card.
    func apply(_ value: KCFieldValue, to card: KnowledgeCard) {
        switch (self, value) {
        case (.title, .text(let s)): card.title = s
        case (.narrative, .text(let s)): card.narrative = s
        case (.cardType, .optionalText(let s)): card.cardType = s.flatMap { CardType(rawValue: $0) }
        case (.dateRange, .optionalText(let s)): card.dateRange = s
        case (.organization, .optionalText(let s)): card.organization = s
        case (.location, .optionalText(let s)): card.location = s
        case (.evidenceQuality, .optionalText(let s)): card.evidenceQuality = s
        case (.domains, .list(let a)):
            let e = card.extractable
            card.extractable = ExtractableMetadata(domains: a, scale: e.scale, keywords: e.keywords)
        case (.scale, .list(let a)):
            let e = card.extractable
            card.extractable = ExtractableMetadata(domains: e.domains, scale: a, keywords: e.keywords)
        case (.keywords, .list(let a)):
            let e = card.extractable
            card.extractable = ExtractableMetadata(domains: e.domains, scale: e.scale, keywords: a)
        case (.technologies, .list(let a)): card.technologies = a
        case (.outcomes, .list(let a)): card.outcomes = a
        case (.suggestedBullets, .list(let a)): card.suggestedBullets = a
        case (.facts, .facts(let f)):
            card.facts = f.map {
                KnowledgeCardFact(category: $0.category, statement: $0.statement, confidence: $0.confidence, source: nil)
            }
        case (.verbatimExcerpts, .excerpts(let e)):
            card.verbatimExcerpts = e.map {
                VerbatimExcerpt(context: $0.context, location: $0.location, text: $0.text, preservationReason: $0.preservationReason)
            }
        default:
            break
        }
    }

    private func decodeArray<T: Decodable>(_ raw: Any?, as type: T.Type) -> [T] {
        guard let raw,
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let decoded = try? JSONDecoder().decode([T].self, from: data) else {
            return []
        }
        return decoded
    }
}

/// The typed value of a knowledge-card field, used for diff comparison, display,
/// and apply. Heterogeneous fields collapse into a handful of shapes.
enum KCFieldValue: Equatable {
    case text(String)
    case optionalText(String?)
    case list([String])
    case facts([RefinedFact])
    case excerpts([RefinedExcerpt])

    /// Human-readable rendering for the before/after columns.
    var display: String {
        switch self {
        case .text(let s):
            return s.isEmpty ? "—" : s
        case .optionalText(let s):
            return (s?.isEmpty == false) ? s! : "—"
        case .list(let items):
            return items.isEmpty ? "—" : items.map { "• \($0)" }.joined(separator: "\n")
        case .facts(let facts):
            return facts.isEmpty ? "—" : facts.map { "• [\($0.category)] \($0.statement)" }.joined(separator: "\n")
        case .excerpts(let excerpts):
            return excerpts.isEmpty ? "—" : excerpts.map { "• [\($0.context)] \($0.text)" }.joined(separator: "\n\n")
        }
    }
}

/// One reviewable field: its before/after values and the user's decision. The
/// after value is mutable so a per-field retry can replace it in place.
struct KCFieldDiff: Identifiable {
    enum Decision {
        case pending
        case accepted
        case rejected
    }

    let field: KCField
    let beforeValue: KCFieldValue
    var afterValue: KCFieldValue
    var decision: Decision = .pending

    var id: String { field.id }
    var label: String { field.label }
}

extension KCFieldDiff {
    /// Build the set of changed fields between a card and its refinement. Unchanged
    /// fields are omitted — the review screen only shows what the refinement touched.
    static func changedFields(before card: KnowledgeCard, after refined: RefinedKnowledgeCard) -> [KCFieldDiff] {
        KCField.allCases.compactMap { field in
            let before = field.before(from: card)
            let after = field.after(from: refined)
            guard before != after else { return nil }
            return KCFieldDiff(field: field, beforeValue: before, afterValue: after)
        }
    }

    /// Apply every accepted field's after-value onto the card. Pending and rejected
    /// fields are left untouched, so the card keeps its original content for those.
    static func applyAccepted(_ diffs: [KCFieldDiff], to card: KnowledgeCard) {
        for diff in diffs where diff.decision == .accepted {
            diff.field.apply(diff.afterValue, to: card)
        }
    }
}

private extension Optional where Wrapped == String {
    /// Treat whitespace-only / empty strings as `nil` so they don't read as changes.
    var nilIfBlank: String? {
        guard let value = self else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }
}
