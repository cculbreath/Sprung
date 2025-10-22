import AppKit
import Foundation
import SwiftyJSON

struct ApplicantSocialProfileDraft: Identifiable, Equatable {
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

    init(model: ApplicantSocialProfile) {
        self.id = model.id
        self.network = model.network
        self.username = model.username
        self.url = model.url
    }

    func toModel(existing: ApplicantSocialProfile? = nil) -> ApplicantSocialProfile {
        if let existing {
            existing.network = network
            existing.username = username
            existing.url = url
            return existing
        }
        let profile = ApplicantSocialProfile(
            id: id,
            network: network,
            username: username,
            url: url
        )
        return profile
    }
}

struct ApplicantProfileDraft: Equatable {
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
    var socialProfiles: [ApplicantSocialProfileDraft]
    var pictureData: Data?
    var pictureMimeType: String?

    init(
        name: String = "",
        label: String = "",
        summary: String = "",
        address: String = "",
        city: String = "",
        state: String = "",
        zip: String = "",
        countryCode: String = "",
        websites: String = "",
        email: String = "",
        phone: String = "",
        socialProfiles: [ApplicantSocialProfileDraft] = [],
        pictureData: Data? = nil,
        pictureMimeType: String? = nil
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
        self.socialProfiles = socialProfiles
        self.pictureData = pictureData
        self.pictureMimeType = pictureMimeType
    }

    init(profile: ApplicantProfile) {
        self.name = profile.name
        self.label = profile.label
        self.summary = profile.summary
        self.address = profile.address
        self.city = profile.city
        self.state = profile.state
        self.zip = profile.zip
        self.countryCode = profile.countryCode
        self.websites = profile.websites
        self.email = profile.email
        self.phone = profile.phone
        self.socialProfiles = profile.profiles.map(ApplicantSocialProfileDraft.init(model:))
        self.pictureData = profile.pictureData
        self.pictureMimeType = profile.pictureMimeType
    }

    init(json: JSON) {
        self.name = json["name"].stringValue
        self.label = json["label"].stringValue
        self.summary = json["summary"].stringValue
        let location = json["location"]
        self.address = location["address"].string ?? json["address"].stringValue
        self.city = location["city"].string ?? json["city"].stringValue
        self.state = location["state"].string ?? location["region"].string ?? json["state"].stringValue
        self.zip = location["postalCode"].string ?? location["zip"].string ?? json["zip"].stringValue
        self.countryCode = location["countryCode"].string ?? json["country"].stringValue
        self.websites = json["website"].string ?? json["websites"].stringValue
        self.email = json["email"].stringValue
        self.phone = json["phone"].stringValue
        self.socialProfiles = json["profiles"].arrayValue.map { value in
            ApplicantSocialProfileDraft(
                id: UUID(uuidString: value["id"].stringValue) ?? UUID(),
                network: value["network"].stringValue,
                username: value["username"].stringValue,
                url: value["url"].stringValue
            )
        }
        if let image = json["image"].string, let data = Data(base64Encoded: image) {
            self.pictureData = data
            self.pictureMimeType = "image/png"
        } else {
            self.pictureData = nil
            self.pictureMimeType = nil
        }
    }

    mutating func updatePicture(data: Data?, mimeType: String?) {
        pictureData = data
        pictureMimeType = data == nil ? nil : (mimeType ?? pictureMimeType ?? "image/png")
    }

    func merging(_ other: ApplicantProfileDraft) -> ApplicantProfileDraft {
        var merged = self
        if !other.name.isEmpty { merged.name = other.name }
        if !other.label.isEmpty { merged.label = other.label }
        if !other.summary.isEmpty { merged.summary = other.summary }
        if !other.address.isEmpty { merged.address = other.address }
        if !other.city.isEmpty { merged.city = other.city }
        if !other.state.isEmpty { merged.state = other.state }
        if !other.zip.isEmpty { merged.zip = other.zip }
        if !other.countryCode.isEmpty { merged.countryCode = other.countryCode }
        if !other.websites.isEmpty { merged.websites = other.websites }
        if !other.email.isEmpty { merged.email = other.email }
        if !other.phone.isEmpty { merged.phone = other.phone }
        if !other.socialProfiles.isEmpty { merged.socialProfiles = other.socialProfiles }
        if let pictureData = other.pictureData, !pictureData.isEmpty {
            merged.pictureData = pictureData
            merged.pictureMimeType = other.pictureMimeType
        }
        return merged
    }

    func apply(to profile: ApplicantProfile) {
        profile.name = name
        profile.label = label
        profile.summary = summary
        profile.address = address
        profile.city = city
        profile.state = state
        profile.zip = zip
        profile.countryCode = countryCode
        profile.websites = websites
        profile.email = email
        profile.phone = phone

        var existing = Dictionary(uniqueKeysWithValues: profile.profiles.map { ($0.id, $0) })
        var updatedProfiles: [ApplicantSocialProfile] = []
        for draft in socialProfiles {
            let existingProfile = existing.removeValue(forKey: draft.id)
            let updated = draft.toModel(existing: existingProfile)
            updatedProfiles.append(updated)
        }
        profile.profiles = updatedProfiles
        profile.pictureData = pictureData
        profile.pictureMimeType = pictureMimeType
    }

    func toJSON() -> JSON {
        var location: [String: Any] = [:]
        if !address.isEmpty { location["address"] = address }
        if !city.isEmpty { location["city"] = city }
        if !state.isEmpty { location["region"] = state }
        if !zip.isEmpty { location["postalCode"] = zip }
        if !countryCode.isEmpty { location["countryCode"] = countryCode }

        var payload: [String: Any] = [
            "name": name,
            "label": label,
            "summary": summary,
            "website": websites,
            "email": email,
            "phone": phone,
            "location": location
        ]

        if !socialProfiles.isEmpty {
            payload["profiles"] = socialProfiles.map { profile in
                [
                    "id": profile.id.uuidString,
                    "network": profile.network,
                    "username": profile.username,
                    "url": profile.url
                ]
            }
        }

        if let pictureData, !pictureData.isEmpty {
            payload["image"] = pictureData.base64EncodedString()
            if let mimeType = pictureMimeType {
                payload["image_mime_type"] = mimeType
            }
        }

        return JSON(payload)
    }

    var pictureImage: NSImage? {
        guard let pictureData else { return nil }
        return NSImage(data: pictureData)
    }
}
