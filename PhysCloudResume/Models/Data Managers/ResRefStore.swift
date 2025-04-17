import Foundation
import Observation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class ResRefStore {
    private unowned let modelContext: ModelContext
    // Computed collection
    var resRefs: [ResRef] {
        (try? modelContext.fetch(FetchDescriptor<ResRef>())) ?? []
    }

    private var changeToken: Int = 0

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
        withAnimation { changeToken += 1 }
    }

    /// Persists updates (entity already mutated)
    func updateResRef(_ resRef: ResRef) {
        do {
            try modelContext.save()
            withAnimation { changeToken += 1 }
        } catch {
            print("ResRefStore: failed to save update \(error)")
        }
    }

    /// Deletes a `ResRef` from the store
    func deleteResRef(_ resRef: ResRef) {
        modelContext.delete(resRef)
        try? modelContext.save()
        withAnimation { changeToken += 1 }
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
