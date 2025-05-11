//
//  SwiftDataStore.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/20/25.
//

//  SwiftDataStore.swift
//  PhysCloudResume
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
    func saveContext(file _: StaticString = #fileID, line _: UInt = #line) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            #if DEBUG
            #endif
            return false
        }
    }

    /// Inserts the entity into the context *and* persists immediately.  The
    /// helper keeps call‑sites short and frees them from having to remember to
    /// call `saveContext()` manually.
    @discardableResult
    func persist<T: PersistentModel>(_ entity: T) -> T {
        modelContext.insert(entity)
        _ = saveContext()
        return entity
    }
}
