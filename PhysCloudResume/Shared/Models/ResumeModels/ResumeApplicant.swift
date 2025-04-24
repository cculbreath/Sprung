//
//  ResumeApplicant.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/25/24.
//

import Foundation
import SwiftData
import SwiftUI

@Model
class ApplicantProfile {
    var name: String
    var address: String
    var city: String
    var state: String
    var zip: String
    var websites: String
    var email: String
    var phone: String
    var signatureData: Data?

    init(
        name: String = "Christopher Culbreath",
        address: String = "7317 Shadywood Drive",
        city: String = "Austin",
        state: String = "Texas",
        zip: String = "78745",
        websites: String = "culbreath.net",
        email: String = "cc@physicscloud.net",
        phone: String = "(805) 234-0847",
        signatureData: Data? = nil
    ) {
        self.name = name
        self.address = address
        self.city = city
        self.state = state
        self.zip = zip
        self.websites = websites
        self.email = email
        self.phone = phone
        self.signatureData = signatureData
    }

    // Helper to convert signature data to image
    func getSignatureImage() -> Image? {
        guard let data = signatureData else { return nil }

        if let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }

        return nil
    }
}

// Legacy struct for backward compatibility during transition
struct Applicant {
    var profile: ApplicantProfile

    @MainActor
    init(profile: ApplicantProfile? = nil) {
        self.profile = profile ?? ApplicantProfileManager.shared.getProfile()
    }

    // Non-MainActor initializer that directly sets values - for use in non-MainActor contexts
    init(
        name: String,
        address: String,
        city: String,
        state: String,
        zip: String,
        websites: String,
        email: String,
        phone: String
    ) {
        // Create a standalone ApplicantProfile without accessing MainActor-isolated code
        profile = ApplicantProfile(
            name: name,
            address: address,
            city: city,
            state: state,
            zip: zip,
            websites: websites,
            email: email,
            phone: phone
        )
    }

    // Forward properties to maintain backward compatibility
    var name: String { profile.name }
    var address: String { profile.address }
    var city: String { profile.city }
    var state: String { profile.state }
    var zip: String { profile.zip }
    var websites: String { profile.websites }
    var email: String { profile.email }
    var phone: String { profile.phone }
}

// Singleton manager for ApplicantProfile
@MainActor
class ApplicantProfileManager {
    static let shared = ApplicantProfileManager()
    private var cachedProfile: ApplicantProfile?
    private var modelContainer: ModelContainer?

    private init() {
        setupModelContainer()
    }

    /// Creates a `ModelContainer` that is schema‑compatible with the container
    /// defined at the application root.  Using the same full set of model
    /// types prevents SQLite migration problems that occur when multiple
    /// containers that reference the same underlying store are created with
    /// different schemas.  (The crash reported as *no such table: ZJOBAPP* was
    /// a direct result of this mismatch.)
    ///
    /// We therefore build the container with **all** model types that the main
    /// application declares instead of only `ApplicantProfile`.  That way every
    /// `ModelContainer` in the process shares an identical schema and can
    /// safely coexist while pointing at the same `default.store` file.
    private func setupModelContainer() {
        do {
            // Keep this list in sync with PhysicsCloudResumeApp.modelContainer(for:)
            modelContainer = try ModelContainer(for:
                JobApp.self,
                Resume.self,
                ResRef.self,
                TreeNode.self,
                FontSizeNode.self,
                CoverLetter.self,
                MessageParams.self,
                CoverRef.self,
                ApplicantProfile.self,
                ResModel.self)
        } catch {
            print("Failed to create model container with all models: \(error)")
        }
    }

    func getProfile() -> ApplicantProfile {
        if let cachedProfile {
            return cachedProfile
        }

        // Try to load from SwiftData
        if let loadedProfile = loadProfileFromSwiftData() {
            cachedProfile = loadedProfile
            return loadedProfile
        }

        // Create default profile if none exists
        let defaultProfile = ApplicantProfile()
        saveProfile(defaultProfile)
        cachedProfile = defaultProfile
        return defaultProfile
    }

    private func loadProfileFromSwiftData() -> ApplicantProfile? {
        guard let context = modelContainer?.mainContext else {
            print("Model container not initialized")
            return nil
        }

        do {
            let descriptor = FetchDescriptor<ApplicantProfile>(sortBy: [])
            let profiles = try context.fetch(descriptor)
            return profiles.first
        } catch {
            print("Failed to load ApplicantProfile: \(error)")
            return nil
        }
    }

    func saveProfile(_ profile: ApplicantProfile) {
        guard let context = modelContainer?.mainContext else {
            print("Model container not initialized")
            return
        }

        do {
            // Check if we already have a profile
            let descriptor = FetchDescriptor<ApplicantProfile>(sortBy: [])
            let existingProfiles = try context.fetch(descriptor)

            if let existingProfile = existingProfiles.first {
                // Update existing profile
                existingProfile.name = profile.name
                existingProfile.address = profile.address
                existingProfile.city = profile.city
                existingProfile.state = profile.state
                existingProfile.zip = profile.zip
                existingProfile.websites = profile.websites
                existingProfile.email = profile.email
                existingProfile.phone = profile.phone
                existingProfile.signatureData = profile.signatureData
            } else {
                // Insert new profile
                context.insert(profile)
            }

            try context.save()
            cachedProfile = profile
        } catch {
            print("Failed to save ApplicantProfile: \(error)")
        }
    }
}
