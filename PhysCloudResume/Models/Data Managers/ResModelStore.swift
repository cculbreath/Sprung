import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ResModelStore {
    private unowned let modelContext: ModelContext
    var resModels: [ResModel] = []
    var resStore: ResStore

    var isThereAnyJson: Bool { !resModels.isEmpty }

    init(context: ModelContext, resStore: ResStore) {
        self.modelContext = context
        self.resStore = resStore
        loadModels()
        print("Model Store Init: \(resModels.count) models")
    }

    private func loadModels() {
        let descriptor = FetchDescriptor<ResModel>()
        do {
            resModels = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to fetch Resume Models: \(error)")
        }
    }

    /// Ensures that each modelRef is unique across `resRefs`

    /// Adds a new `ResRef` to the store
    func addResModel(_ resModel: ResModel) {
        resModels.append(resModel)
        modelContext.insert(resModel)
        try! saveContext()
    }

    /// Updates an existing `ResRef` if found
    func updateResModel(_ resModel: ResModel) {
        if let index = resModels.firstIndex(where: { $0.id == resModel.id }) {
            resModels[index] = resModel
            try? saveContext()
        }
    }

    /// Deletes a `ResRef` from the store
    func deleteResModel(_ resModel: ResModel) {
        if let index = resModels.firstIndex(where: { $0.id == resModel.id }) {
            for myRes in resModels[index].resumes {
                resStore.deleteRes(myRes)
            }

            resModels.remove(at: index)
        modelContext.delete(resModel)
            do {
                try saveContext()
            } catch {
                print("deleteRes")
            }
        }
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
