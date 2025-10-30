import Foundation

/// Shared utilities for interaction handlers to reduce boilerplate.
extension Optional where Wrapped == UUID {
    /// Guard that an optional continuation ID exists, logging a warning if missing.
    /// Returns the ID if present, or nil if absent (with warning logged).
    func guardContinuation(
        operation: String,
        category: Logger.Category = .ai
    ) -> UUID? {
        guard let id = self else {
            Logger.warning("⚠️ No pending \(operation) to resolve", category: category)
            return nil
        }
        return id
    }
}
