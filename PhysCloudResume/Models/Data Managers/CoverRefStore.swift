import Foundation
import SwiftData

@Observable
final class CoverRefStore {
    var storedCoverRefs: [CoverRef] = []
    private var modelContext: ModelContext?

    var defaultSources: [CoverRef] {
        return storedCoverRefs.filter { $0.enabledByDefault == true }
    }

    init() {}

    func initialize(context: ModelContext) {
        modelContext = context
        loadCoverRefs() // Load data from the database when the store is initialized
    }

    var backgroundFacts: [CoverRef] {
        return storedCoverRefs.filter { $0.type == .backgroundFact }
    }

    var writingSamples: [CoverRef] {
        return storedCoverRefs.filter { $0.type == .writingSample }
    }

    private func loadCoverRefs() {
        let descriptor = FetchDescriptor<CoverRef>()
        do {
            storedCoverRefs = try modelContext!.fetch(descriptor)
        } catch {
            print("Failed to fetch Cover Refs: \(error)")
        }
    }

    @discardableResult
    func addCoverRef(_ coverRef: CoverRef) -> CoverRef {
        storedCoverRefs.append(coverRef)
        modelContext?.insert(coverRef)
        saveContext()
        return coverRef
    }

    func deleteCoverRef(_ coverRef: CoverRef) {
        if let index = storedCoverRefs.firstIndex(of: coverRef) {
            storedCoverRefs.remove(at: index)
            modelContext?.delete(coverRef)
            saveContext()
        }
    }

    private func saveContext() {
        do {
            try modelContext?.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}
