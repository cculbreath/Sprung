import Foundation
import SwiftData

@Observable
@MainActor
final class CoverRefStore {
    private unowned let modelContext: ModelContext
    var storedCoverRefs: [CoverRef] = []

    var defaultSources: [CoverRef] {
        storedCoverRefs.filter { $0.enabledByDefault }
    }

    init(context: ModelContext) {
        self.modelContext = context
        loadCoverRefs()
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
            storedCoverRefs = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to fetch Cover Refs: \(error)")
        }
    }

    @discardableResult
    func addCoverRef(_ coverRef: CoverRef) -> CoverRef {
        storedCoverRefs.append(coverRef)
        modelContext.insert(coverRef)
        saveContext()
        return coverRef
    }

    func deleteCoverRef(_ coverRef: CoverRef) {
        if let index = storedCoverRefs.firstIndex(of: coverRef) {
            storedCoverRefs.remove(at: index)
            modelContext.delete(coverRef)
            saveContext()
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}
