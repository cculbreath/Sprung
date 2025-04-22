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
    
    init(profile: ApplicantProfile? = nil) {
        self.profile = profile ?? ApplicantProfileManager.shared.getProfile()
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
class ApplicantProfileManager {
    static let shared = ApplicantProfileManager()
    private var cachedProfile: ApplicantProfile?
    
    private init() {}
    
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
        do {
            let modelContainer = try ModelContainer(for: ApplicantProfile.self)
            let context = modelContainer.mainContext
            let descriptor = FetchDescriptor<ApplicantProfile>(sortBy: [])
            let profiles = try context.fetch(descriptor)
            return profiles.first
        } catch {
            print("Failed to load ApplicantProfile: \(error)")
            return nil
        }
    }
    
    func saveProfile(_ profile: ApplicantProfile) {
        do {
            let modelContainer = try ModelContainer(for: ApplicantProfile.self)
            let context = modelContainer.mainContext
            
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