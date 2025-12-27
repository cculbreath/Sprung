//
//  Applicant.swift
//  Sprung
//
import Foundation
import SwiftData
import SwiftUI

// MARK: - Social Profile (Codable struct, stored as JSON in ApplicantProfile)

struct SocialProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var network: String
    var username: String
    var url: String

    init(
        id: UUID = UUID(),
        network: String = "",
        username: String = "",
        url: String = ""
    ) {
        self.id = id
        self.network = network
        self.username = username
        self.url = url
    }
}

// MARK: - Applicant Profile

@Model
class ApplicantProfile {
    var name: String
    var label: String
    var summary: String
    var address: String
    var city: String
    var state: String
    var zip: String
    var countryCode: String
    var websites: String
    var email: String
    var phone: String

    // Social profiles stored as JSON blob
    private var socialProfilesData: Data?

    var profiles: [SocialProfile] {
        get {
            guard let data = socialProfilesData,
                  let decoded = try? JSONDecoder().decode([SocialProfile].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            socialProfilesData = try? JSONEncoder().encode(newValue)
        }
    }

    @Attribute(.externalStorage) var pictureData: Data?
    var pictureMimeType: String?
    var signatureData: Data?

    init(
        name: String = "John Doe",
        label: String = "Software Engineer",
        summary: String = "Experienced engineer focused on building high-quality macOS applications.",
        address: String = "123 Main Street",
        city: String = "Austin",
        state: String = "Texas",
        zip: String = "78701",
        countryCode: String = "US",
        websites: String = "example.com",
        email: String = "applicant@example.com",
        phone: String = "(555) 123-4567",
        profiles: [SocialProfile] = [],
        pictureData: Data? = nil,
        pictureMimeType: String? = nil,
        signatureData: Data? = nil
    ) {
        self.name = name
        self.label = label
        self.summary = summary
        self.address = address
        self.city = city
        self.state = state
        self.zip = zip
        self.countryCode = countryCode
        self.websites = websites
        self.email = email
        self.phone = phone
        self.profiles = profiles
        self.pictureData = pictureData
        self.pictureMimeType = pictureMimeType
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
    func getPictureImage() -> Image? {
        guard let data = pictureData,
              let nsImage = NSImage(data: data) else {
            return nil
        }
        return Image(nsImage: nsImage)
    }
    func pictureDataURL() -> String? {
        guard let pictureData else { return nil }
        let mimeType = pictureMimeType ?? "image/png"
        let base64 = pictureData.base64EncodedString()
        return "data:\(mimeType);base64,\(base64)"
    }
    func updatePicture(data: Data?, mimeType: String?) {
        pictureData = data
        pictureMimeType = data == nil ? nil : (mimeType ?? pictureMimeType ?? "image/png")
    }
}
struct Applicant {
    var profile: ApplicantProfile
    init(profile: ApplicantProfile) {
        self.profile = profile
    }
    init(
        name: String,
        label: String,
        summary: String,
        address: String,
        city: String,
        state: String,
        zip: String,
        websites: String,
        email: String,
        phone: String,
        profiles: [SocialProfile] = [],
        pictureData: Data? = nil,
        pictureMimeType: String? = nil
    ) {
        // Create a standalone ApplicantProfile without accessing MainActor-isolated code
        profile = ApplicantProfile(
            name: name,
            label: label,
            summary: summary,
            address: address,
            city: city,
            state: state,
            zip: zip,
            websites: websites,
            email: email,
            phone: phone,
            profiles: profiles,
            pictureData: pictureData,
            pictureMimeType: pictureMimeType
        )
    }
    // Forward properties to maintain backward compatibility
    var name: String { profile.name }
    var label: String { profile.label }
    var summary: String { profile.summary }
    var address: String { profile.address }
    var city: String { profile.city }
    var state: String { profile.state }
    var zip: String { profile.zip }
    var websites: String { profile.websites }
    var email: String { profile.email }
    var phone: String { profile.phone }
    var pictureDataURL: String? { profile.pictureDataURL() }
    var picture: String { profileDataURL ?? "" }
    private var profileDataURL: String? { profile.pictureDataURL() }
    /// Provides a non-empty placeholder applicant for previews and fallbacks.
    static var placeholder: Applicant {
        Applicant(
            name: "Alex Applicant",
            label: "Product Designer",
            summary: "Design leader focused on crafting elegant user experiences across macOS and iOS.",
            address: "123 Sample Street",
            city: "Sample City",
            state: "Example State",
            zip: "00000",
            websites: "example.com",
            email: "applicant@example.com",
            phone: "(555) 010-0000"
        )
    }
}
