import Foundation
import SwiftData

@Observable
@MainActor
final class CoverRefStore {
    private unowned let modelContext: ModelContext
    var storedCoverRefs: [CoverRef] {
        (try? modelContext.fetch(FetchDescriptor<CoverRef>())) ?? []
    }


    var defaultSources: [CoverRef] {
        storedCoverRefs.filter { $0.enabledByDefault }
    }

    init(context: ModelContext) {
        self.modelContext = context
    }

    var backgroundFacts: [CoverRef] {
        return storedCoverRefs.filter { $0.type == .backgroundFact }
    }

    var writingSamples: [CoverRef] {
        return storedCoverRefs.filter { $0.type == .writingSample }
    }



    @discardableResult
    func addCoverRef(_ coverRef: CoverRef) -> CoverRef {
        modelContext.insert(coverRef)
        try? modelContext.save()

        return coverRef
    }

    func deleteCoverRef(_ coverRef: CoverRef) {
        modelContext.delete(coverRef)
        try? modelContext.save()

    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}
