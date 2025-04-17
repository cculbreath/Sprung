import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class CoverRefStore {
    private unowned let modelContext: ModelContext
    var storedCoverRefs: [CoverRef] {
        (try? modelContext.fetch(FetchDescriptor<CoverRef>())) ?? []
    }

    private var changeToken: Int = 0

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
        withAnimation { changeToken += 1 }
        return coverRef
    }

    func deleteCoverRef(_ coverRef: CoverRef) {
        modelContext.delete(coverRef)
        try? modelContext.save()
        withAnimation { changeToken += 1 }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}
