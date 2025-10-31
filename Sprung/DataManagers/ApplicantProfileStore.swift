//
//  ApplicantProfileStore.swift
//  Sprung
//

import Foundation
import Observation
import SwiftData

@MainActor
protocol ApplicantProfileProviding: AnyObject {
    func currentProfile() -> ApplicantProfile
    func save(_ profile: ApplicantProfile)
}

@Observable
@MainActor
final class ApplicantProfileStore: SwiftDataStore, ApplicantProfileProviding {
    // MARK: - Properties

    let modelContext: ModelContext
    private var cachedProfile: ApplicantProfile?

    init(context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Public API

    func currentProfile() -> ApplicantProfile {
        if let cachedProfile {
            return cachedProfile
        }

        if let existing = try? modelContext.fetch(FetchDescriptor<ApplicantProfile>()).first {
            cachedProfile = existing
            return existing
        }

        let profile = ApplicantProfile()
        modelContext.insert(profile)
        cachedProfile = profile
        saveContext()
        return profile
    }

    func save(_ profile: ApplicantProfile) {
        if profile.modelContext == nil {
            modelContext.insert(profile)
        }
        cachedProfile = profile
        saveContext()
    }

    func clearCache() {
        cachedProfile = nil
    }
}
