//
//  SwiftDataStore.swift
//  Sprung
//
//  A protocol that provides a shared `saveContext()` helper for stores
//  that hold a SwiftData `ModelContext`. Uses weak reference to avoid
//  crashes during container teardown.
//
import Foundation
import SwiftData

@MainActor
protocol SwiftDataStore: AnyObject {
    /// The model context for SwiftData persistence.
    var modelContext: ModelContext { get }
}

extension SwiftDataStore {
    /// Attempts to `save()` and logs any thrown error (in *debug* builds only)
    /// so production performance isn't impacted.
    /// Returns false if save fails.
    @discardableResult
    func saveContext(file: StaticString = #fileID, line: UInt = #line) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            #if DEBUG
            Logger.error(
                "SwiftData save failed: \(error.localizedDescription)",
                category: .storage,
                metadata: [
                    "file": String(describing: file),
                    "line": String(line)
                ]
            )
            #endif
            return false
        }
    }
}
