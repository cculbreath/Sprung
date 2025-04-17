import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ResRefStore {
    private unowned let modelContext: ModelContext
    // Computed collection
    var resRefs: [ResRef] {
        (try? modelContext.fetch(FetchDescriptor<ResRef>())) ?? []
    }


    var defaultSources: [ResRef] {
        resRefs.filter { $0.enabledByDefault }
    }

    init(context: ModelContext) {
        self.modelContext = context
        print("RefStore Initialized: \(resRefs.count) refs")
    }



    /// Adds a new `ResRef` to the store
    func addResRef(_ resRef: ResRef) {
        modelContext.insert(resRef)
        try? modelContext.save()

    }

    /// Persists updates (entity already mutated)
    func updateResRef(_ resRef: ResRef) {
        do {
            try modelContext.save()

        } catch {
            print("ResRefStore: failed to save update \(error)")
        }
    }

    /// Deletes a `ResRef` from the store
    func deleteResRef(_ resRef: ResRef) {
        modelContext.delete(resRef)
        try? modelContext.save()

    }

    /// Persists changes to the database
    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}
