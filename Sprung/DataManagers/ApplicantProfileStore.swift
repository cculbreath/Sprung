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

    /// Reset the applicant profile to default values (including clearing photo)
    func reset() {
        let profile = currentProfile()
        // Reset all fields to defaults
        profile.name = "John Doe"
        profile.label = "Software Engineer"
        profile.summary = "Experienced engineer focused on building high-quality macOS applications."
        profile.address = "123 Main Street"
        profile.city = "Austin"
        profile.state = "Texas"
        profile.zip = "78701"
        profile.countryCode = "US"
        profile.websites = "example.com"
        profile.email = "applicant@example.com"
        profile.phone = "(555) 123-4567"
        profile.pictureData = nil
        profile.pictureMimeType = nil
        profile.signatureData = nil
        // Clear social profiles
        profile.profiles.removeAll()
        save(profile)
        Logger.info("🔄 ApplicantProfile reset to defaults", category: .ai)
    }
}
