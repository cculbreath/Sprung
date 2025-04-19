import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ResRefStore: SwiftDataStore {
    private unowned let modelContext: ModelContext
    // JSON backup for ResRef
    private let jsonBacking = JSONFileStore<ResRef>(filename: "ResRefs.json")
    // Computed collection
    var resRefs: [ResRef] {
        (try? modelContext.fetch(FetchDescriptor<ResRef>())) ?? []
    }

    var defaultSources: [ResRef] {
        resRefs.filter { $0.enabledByDefault }
    }

    init(context: ModelContext) {
        modelContext = context
        // Import JSON backup into SwiftData (one-way)
        do {
            let loaded: [ResRef] = try jsonBacking.load()
            for ref in loaded where (try? modelContext.fetch(
                FetchDescriptor<ResRef>(predicate: #Predicate { $0.id == ref.id })
            ))?.isEmpty ?? true {
                modelContext.insert(ref)
            }
        } catch {
            #if DEBUG
            print("ResRefStore: Failed to import JSON backup – \(error)")
            #endif
        }
        print("RefStore Initialized: \(resRefs.count) refs")
    }

    /// Adds a new `ResRef` to the store
    func addResRef(_ resRef: ResRef) {
        modelContext.insert(resRef)
        saveContext()
        persistToJSON()
    }

    /// Persists updates (entity already mutated)
    func updateResRef(_ resRef: ResRef) {
        _ = saveContext()
        persistToJSON()
    }

    /// Deletes a `ResRef` from the store
    func deleteResRef(_ resRef: ResRef) {
        modelContext.delete(resRef)
        saveContext()
        persistToJSON()
    }

    /// Persists changes to the database
    // MARK: - JSON File Backing
    /// Serialises the current collection to disk. Failures are ignored in production.
    private func persistToJSON() {
        #if DEBUG
        do {
            try jsonBacking.save(resRefs)
        } catch {
            print("ResRefStore: Failed to write JSON backup – \(error)")
        }
        #else
        try? jsonBacking.save(resRefs)
        #endif
    }
    // `saveContext()` now from `SwiftDataStore`.
}
