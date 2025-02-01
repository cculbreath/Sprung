import Foundation
import Observation
import SwiftData

@Observable
final class ResRefStore {
    var resRefs: [ResRef] = []

    var defaultSources: [ResRef] {
        return resRefs.filter { $0.enabledByDefault == true }
    }

    private var modelContext: ModelContext?

    init() {}

    func initialize(context: ModelContext) {
        modelContext = context
        loadResRefs() // Load data from database on init
        print("RefStore Initialized: \(resRefs.count) refs")
    }

    private func loadResRefs() {
        let descriptor = FetchDescriptor<ResRef>()
        do {
            resRefs = try modelContext!.fetch(descriptor)
        } catch {
            print("Failed to fetch Resume Refs: \(error)")
        }
    }

    /// Adds a new `ResRef` to the store
    func addResRef(_ resRef: ResRef) {
        resRefs.append(resRef)
        modelContext?.insert(resRef)
        saveContext()
    }

    /// Updates an existing `ResRef` if found
    func updateResRef(_ resRef: ResRef) {
        if let index = resRefs.firstIndex(where: { $0.id == resRef.id }) {
            resRefs[index] = resRef
            saveContext()
        }
    }

    /// Deletes a `ResRef` from the store
    func deleteResRef(_ resRef: ResRef) {
        if let index = resRefs.firstIndex(where: { $0.id == resRef.id }) {
            resRefs.remove(at: index)
            modelContext?.delete(resRef)
            saveContext()
        }
    }

    /// Persists changes to the database
    private func saveContext() {
        do {
            try modelContext?.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}
