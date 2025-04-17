import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ResModelStore {
    private unowned let modelContext: ModelContext
    var resModels: [ResModel] {
        (try? modelContext.fetch(FetchDescriptor<ResModel>())) ?? []
    }

    var resStore: ResStore

    var isThereAnyJson: Bool { !resModels.isEmpty }

    init(context: ModelContext, resStore: ResStore) {
        self.modelContext = context
        self.resStore = resStore
        print("Model Store Init: \(resModels.count) models")
    }



    /// Ensures that each modelRef is unique across `resRefs`

    /// Adds a new model to the store
    func addResModel(_ resModel: ResModel) {
        modelContext.insert(resModel)
        try? modelContext.save()

    }

    /// Persist updates on the supplied model
    func updateResModel(_ resModel: ResModel) {
        do {
            try modelContext.save()

        } catch {
            print("ResModelStore: update failed \(error)")
        }
    }

    /// Deletes a model and associated resumes
    func deleteResModel(_ resModel: ResModel) {
        for myRes in resModel.resumes {
            resStore.deleteRes(myRes)
        }

        modelContext.delete(resModel)
        try? modelContext.save()

    }

    /// Enforces uniqueness when a `ResRef` is assigned a `modelRef`

    /// Persists changes to the database
    private func saveContext() throws {
        do {
            try modelContext.save()
        } catch {
            throw error // Propagate the error to the caller
        }
    }
}
