import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ResModelStore: SwiftDataStore {
    unowned let modelContext: ModelContext
    // SwiftData is now the single source of truth – no JSON backup.
    var resModels: [ResModel] {
        (try? modelContext.fetch(FetchDescriptor<ResModel>())) ?? []
    }

    var resStore: ResStore

    var isThereAnyJson: Bool { !resModels.isEmpty }

    init(context: ModelContext, resStore: ResStore) {
        modelContext = context
        self.resStore = resStore
        print("Model Store Init: \(resModels.count) models")
    }

    /// Ensures that each modelRef is unique across `resRefs`

    /// Adds a new model to the store
    func addResModel(_ resModel: ResModel) {
        modelContext.insert(resModel)
        saveContext()
    }

    /// Persist updates on the supplied model
    func updateResModel(_: ResModel) {
        _ = saveContext()
    }

    /// Deletes a model and associated resumes
    func deleteResModel(_ resModel: ResModel) {
        for myRes in resModel.resumes {
            resStore.deleteRes(myRes)
        }

        modelContext.delete(resModel)
        saveContext()
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

    // `saveContext()` now in `SwiftDataStore`.
}
