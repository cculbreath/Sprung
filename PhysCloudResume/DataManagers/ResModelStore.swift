//
//  ResModelStore.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

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

    init(context: ModelContext, resStore: ResStore) {
        modelContext = context
        self.resStore = resStore
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

    // `saveContext()` now in `SwiftDataStore`.
}
