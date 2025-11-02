import Foundation

enum ModelPreferenceValidator {
    static func sanitize(
        requested: String,
        available: [String],
        fallback: String
    ) -> (id: String, adjusted: Bool) {
        if available.contains(requested) {
            return (requested, false)
        }

        if available.contains(fallback) {
            return (fallback, true)
        }

        if let first = available.first {
            return (first, true)
        }

        return (fallback, true)
    }
}
