//
//  SwiftDataStore.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/20/25.
//
//  SwiftDataStore.swift
//  Sprung
//
//  A tiny protocol that removes the repetitive `saveContext()` helper that
//  was manually copied into every store class.  Any store that holds a
//  SwiftData `ModelContext` can now adopt `SwiftDataStore` to gain a default
//  implementation of `saveContext()` (along with a convenience `persist(_:)`
//  wrapper for one‑off entity inserts).
import Foundation
import SwiftData
@MainActor
protocol SwiftDataStore: AnyObject {
    var modelContext: ModelContext { get }
}
extension SwiftDataStore {
    /// Attempts to `save()` and logs any thrown error (in *debug* builds only)
    /// so production performance isn't impacted.
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
