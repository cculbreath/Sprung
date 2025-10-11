//
//  CoverRefStore.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/12/24.
//

import Foundation
import SwiftData

@Observable
@MainActor
final class CoverRefStore: SwiftDataStore {
    unowned let modelContext: ModelContext
    var storedCoverRefs: [CoverRef] {
        (try? modelContext.fetch(FetchDescriptor<CoverRef>())) ?? []
    }

    var defaultSources: [CoverRef] {
        storedCoverRefs.filter { $0.enabledByDefault }
    }

    init(context: ModelContext) {
        modelContext = context

        // No JSON import – SwiftData is the single source of truth.
    }

    @discardableResult
    func addCoverRef(_ coverRef: CoverRef) -> CoverRef {
        modelContext.insert(coverRef)
        saveContext()
        return coverRef
    }

    func deleteCoverRef(_ coverRef: CoverRef) {
        modelContext.delete(coverRef)
        saveContext()
    }

    // No JSON File backing – SwiftData only.

    // `saveContext()` now lives in `SwiftDataStore`.
}
