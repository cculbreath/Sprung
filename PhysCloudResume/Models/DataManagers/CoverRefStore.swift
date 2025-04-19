import Foundation
import SwiftData

@Observable
@MainActor
final class CoverRefStore: SwiftDataStore {
    private unowned let modelContext: ModelContext
    var storedCoverRefs: [CoverRef] {
        (try? modelContext.fetch(FetchDescriptor<CoverRef>())) ?? []
    }

    var defaultSources: [CoverRef] {
        storedCoverRefs.filter { $0.enabledByDefault }
    }

    init(context: ModelContext) {
        modelContext = context

        // Sync persistent on‑disk JSON into SwiftData on launch.  Because the
        // entities might have been mutated while the app was offline we do a
        // one‑way import (JSON ➞ SwiftData) at start‑up and write back to JSON
        // whenever local changes occur.
        do {
            let loaded: [CoverRef] = try jsonBacking.load()
            for ref in loaded where (try? modelContext.fetch(
                FetchDescriptor<CoverRef>(predicate: #Predicate { $0.id == ref.id })
            ))?.isEmpty ?? true {
                modelContext.insert(ref)
            }
        } catch {
            #if DEBUG
            print("CoverRefStore: Failed to import JSON backup – \(error)")
            #endif
        }
    }

    var backgroundFacts: [CoverRef] {
        return storedCoverRefs.filter { $0.type == .backgroundFact }
    }

    var writingSamples: [CoverRef] {
        return storedCoverRefs.filter { $0.type == .writingSample }
    }

    @discardableResult
    func addCoverRef(_ coverRef: CoverRef) -> CoverRef {
        modelContext.insert(coverRef)
        saveContext()

        persistToJSON()
        return coverRef
    }

    func deleteCoverRef(_ coverRef: CoverRef) {
        modelContext.delete(coverRef)
        saveContext()

        persistToJSON()
    }
    // MARK: - JSON File Backing

    private let jsonBacking = JSONFileStore<CoverRef>(filename: "CoverRefs.json")

    /// Serialises the current collection to disk.  We **ignore** failures in
    /// production builds because SwiftData is our source‑of‑truth and the app
    /// should continue to function if the backup couldn’t be written.
    private func persistToJSON() {
        #if DEBUG
        do {
            try jsonBacking.save(storedCoverRefs)
        } catch {
            print("CoverRefStore: Failed to write JSON backup – \(error)")
        }
        #else
        try? jsonBacking.save(storedCoverRefs)
        #endif
    }

    // `saveContext()` now lives in `SwiftDataStore`.
}
