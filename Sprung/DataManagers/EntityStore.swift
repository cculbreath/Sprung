//
//  EntityStore.swift
//  Sprung
//
//  Generic CRUD + observation-refresh seam for single-entity SwiftData collection
//  stores. Collapses the add/addAll/delete/deleteAll/update boilerplate that was
//  copy-pasted across ~14 stores, and bakes in the `@Observable` refresh counter
//  that several of those stores were missing entirely — their fetched collections
//  would not reliably re-render in SwiftUI after an insert or delete.
//
//  Why a stored `changeVersion` rather than relying on SwiftData observation:
//  these stores expose their collections as computed `var x: [Entity] { fetch() }`.
//  `@Observable` only tracks stored-property access, not the result of a fetch, so
//  a view reading the collection has no dependency to invalidate when a sibling
//  row is inserted or deleted. `fetchAll()` reads `changeVersion` to register that
//  dependency, and every mutation bumps it — so the view re-renders. A protocol
//  extension cannot add stored storage, so each conformer must DECLARE the counter
//  itself: `var changeVersion: Int = 0` (internal setter — the extension writes it).
//

import Foundation
import SwiftData

@MainActor
protocol EntityStore: SwiftDataStore {
    /// The single `@Model` type this store manages.
    associatedtype Entity: PersistentModel
    /// `@Observable`-tracked refresh counter. Declare as a stored property
    /// (`var changeVersion: Int = 0`); the extension bumps it on every mutation so
    /// SwiftUI views reading the fetched collection re-render on insert/delete.
    var changeVersion: Int { get set }
}

extension EntityStore {
    /// All entities of `Entity`, optionally sorted. Reads `changeVersion` so a
    /// SwiftUI view reading the result establishes a dependency that any mutation
    /// (which bumps the counter) invalidates.
    func fetchAll(sortBy: [SortDescriptor<Entity>] = []) -> [Entity] {
        _ = changeVersion  // establish the observation dependency
        let descriptor = sortBy.isEmpty
            ? FetchDescriptor<Entity>()
            : FetchDescriptor<Entity>(sortBy: sortBy)
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.error("EntityStore failed to fetch \(Entity.self): \(error.localizedDescription)", category: .storage)
            return []
        }
    }

    /// Insert one entity, persist, and trigger a refresh.
    func add(_ entity: Entity) {
        modelContext.insert(entity)
        saveContext()
        changeVersion += 1
    }

    /// Insert many entities, persist once, and trigger a refresh.
    func addAll(_ entities: [Entity]) {
        for entity in entities { modelContext.insert(entity) }
        saveContext()
        changeVersion += 1
    }

    /// Delete one entity, persist, and trigger a refresh.
    func delete(_ entity: Entity) {
        modelContext.delete(entity)
        saveContext()
        changeVersion += 1
    }

    /// Delete many entities, persist once, and trigger a refresh.
    func deleteAll(_ entities: [Entity]) {
        for entity in entities { modelContext.delete(entity) }
        saveContext()
        changeVersion += 1
    }

    /// Persist mutations made directly to an already-managed entity, then refresh.
    /// (Replaces the per-store `update(_:)` boilerplate — SwiftData already tracks
    /// the inserted object, so only save + bump is needed; the argument documents
    /// intent at the call site.)
    func update(_ entity: Entity) {
        saveContext()
        changeVersion += 1
    }

    /// Persist in-place mutations across several already-managed entities, then
    /// refresh. Use after mutating fetched entities in a loop (e.g. bulk approve).
    func persistChanges() {
        saveContext()
        changeVersion += 1
    }
}
