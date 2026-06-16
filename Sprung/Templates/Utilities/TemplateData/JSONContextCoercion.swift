import Foundation
import OrderedCollections

/// Single source of truth for coercing JSON-derived template-context values to a
/// boolean "is this present?" used to drive section/field visibility flags.
///
/// This previously lived as two diverging private `truthy(_:)` copies — one in
/// `ResumeTemplateDataBuilder` (descriptor path) and one in
/// `HandlebarsContextAugmentor` (imported-theme path). They disagreed on
/// whitespace-only strings: the builder treated `"   "` as present (field shown)
/// while the augmentor trimmed and treated it as absent (field hidden), so the
/// same value rendered differently depending on the engine. They also handled
/// `OrderedDictionary` differently. Unifying here fixes both: whitespace-only
/// strings and empty containers (including `OrderedDictionary`) are falsy.
enum JSONContextCoercion {
    /// Whether a context value should be treated as present for a visibility flag.
    /// - `nil` → false
    /// - `NSNumber` (incl. bridged `Bool`) → its `boolValue`
    /// - `String` → false when empty *or* whitespace-only, else true
    /// - arrays / dictionaries / `OrderedDictionary` → false when empty, else true
    /// - anything else → true
    static func truthy(_ value: Any?) -> Bool {
        guard let value else { return false }
        switch value {
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case let array as [Any]:
            return array.isEmpty == false
        case let ordered as OrderedDictionary<String, Any>:
            return ordered.isEmpty == false
        case let dict as [String: Any]:
            return dict.isEmpty == false
        default:
            return true
        }
    }
}
