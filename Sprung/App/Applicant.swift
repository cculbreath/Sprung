//
//  Applicant.swift
//  Sprung
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
    var countryCode: String
    var websites: String
    var email: String
    var phone: String
    @Attribute(.externalStorage) var pictureData: Data?
    var pictureMimeType: String?
    var signatureData: Data?

    init(
        name: String = "John Doe",
        address: String = "123 Main Street",
        city: String = "Austin",
        state: String = "Texas",
        zip: String = "78701",
        countryCode: String = "US",
        websites: String = "example.com",
        email: String = "applicant@example.com",
        phone: String = "(555) 123-4567",
        pictureData: Data? = nil,
        pictureMimeType: String? = nil,
        signatureData: Data? = nil
    ) {
        self.name = name
        self.address = address
        self.city = city
        self.state = state
        self.zip = zip
        self.countryCode = countryCode
        self.websites = websites
        self.email = email
        self.phone = phone
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
        address: String,
        city: String,
        state: String,
        zip: String,
        websites: String,
        email: String,
        phone: String,
        pictureData: Data? = nil,
        pictureMimeType: String? = nil
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
            phone: phone,
            pictureData: pictureData,
            pictureMimeType: pictureMimeType
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
    var pictureDataURL: String? { profile.pictureDataURL() }
    var picture: String { profileDataURL ?? "" }

    private var profileDataURL: String? { profile.pictureDataURL() }
}
