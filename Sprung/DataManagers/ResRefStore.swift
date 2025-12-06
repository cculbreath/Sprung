//
//  ResRefStore.swift
//  Sprung
//
//
import Foundation
import Observation
import SwiftData
@Observable
@MainActor
final class ResRefStore: SwiftDataStore {
    unowned let modelContext: ModelContext
    // Computed collection – SwiftData is now the single source of truth.
    var resRefs: [ResRef] {
        (try? modelContext.fetch(FetchDescriptor<ResRef>())) ?? []
    }
    var defaultSources: [ResRef] {
        resRefs.filter { $0.enabledByDefault }
    }
    init(context: ModelContext) {
        modelContext = context
    }
    /// Adds a new `ResRef` to the store
    func addResRef(_ resRef: ResRef) {
        modelContext.insert(resRef)
        saveContext()
    }
    /// Persists updates (entity already mutated)
    func updateResRef(_: ResRef) {
        _ = saveContext()
    }
    /// Deletes a `ResRef` from the store
    func deleteResRef(_ resRef: ResRef) {
        modelContext.delete(resRef)
        saveContext()
    }

    /// Deletes all ResRefs created during onboarding
    func deleteOnboardingResRefs() {
        let onboardingRefs = resRefs.filter { $0.isFromOnboarding }
        for resRef in onboardingRefs {
            modelContext.delete(resRef)
        }
        saveContext()
        Logger.info("🗑️ Deleted \(onboardingRefs.count) onboarding ResRefs", category: .ai)
    }
    // `saveContext()` now from `SwiftDataStore`.
}
