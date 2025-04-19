import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ResModelStore: SwiftDataStore {
    private unowned let modelContext: ModelContext
    // JSON backup for ResModel
    private let jsonBacking = JSONFileStore<ResModel>(filename: "ResModels.json")
    var resModels: [ResModel] {
        (try? modelContext.fetch(FetchDescriptor<ResModel>())) ?? []
    }

    var resStore: ResStore

    var isThereAnyJson: Bool { !resModels.isEmpty }

    init(context: ModelContext, resStore: ResStore) {
        modelContext = context
        self.resStore = resStore
        // Import JSON backup into SwiftData (one-way)
        do {
            let loaded: [ResModel] = try jsonBacking.load()
            for model in loaded where (try? modelContext.fetch(
                FetchDescriptor<ResModel>(predicate: #Predicate { $0.id == model.id })
            ))?.isEmpty ?? true {
                modelContext.insert(model)
            }
        } catch {
            #if DEBUG
            print("ResModelStore: Failed to import JSON backup – \(error)")
            #endif
        }
        print("Model Store Init: \(resModels.count) models")
    }

    /// Ensures that each modelRef is unique across `resRefs`

    /// Adds a new model to the store
    func addResModel(_ resModel: ResModel) {
        modelContext.insert(resModel)
        saveContext()
        persistToJSON()
    }

    /// Persist updates on the supplied model
    func updateResModel(_ resModel: ResModel) {
        _ = saveContext()
        persistToJSON()
    }

    /// Deletes a model and associated resumes
    func deleteResModel(_ resModel: ResModel) {
        for myRes in resModel.resumes {
            resStore.deleteRes(myRes)
        }

        modelContext.delete(resModel)
        saveContext()
        persistToJSON()
    }

    /// Enforces uniqueness when a `ResRef` is assigned a `modelRef`

    /// Persists changes to the database
    // `saveContext()` now in `SwiftDataStore`. Keeping throwing variant for
    // callers that still need it.
    private func saveContextThrows() throws {
        if !saveContext() {
            throw NSError(domain: "SwiftDataStore", code: 0, userInfo: nil)
        }
    }

    // MARK: - JSON File Backing
    /// Serialises the current collection to disk. Failures are ignored in production.
    private func persistToJSON() {
        #if DEBUG
        do {
            try jsonBacking.save(resModels)
        } catch {
            print("ResModelStore: Failed to write JSON backup – \(error)")
        }
        #else
        try? jsonBacking.save(resModels)
        #endif
    }
}
