import AppKit
import Foundation
import SwiftyJSON

/// Draft model for editing social profiles in the UI
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

    init(model: SocialProfile) {
        self.id = model.id
        self.network = model.network
        self.username = model.username
        self.url = model.url
    }

    func toModel() -> SocialProfile {
        SocialProfile(
            id: id,
            network: network,
            username: username,
            url: url
        )
    }
}
struct ApplicantProfileDraft: Equatable {
    private enum Field: CaseIterable, Hashable {
        case name
        case label
        case summary
        case address
        case city
        case state
        case zip
        case countryCode
        case website
        case email
        case phone
        case socialProfiles
        case picture
    }
    private var providedFields: Set<Field> = []
    var name: String {
        didSet { providedFields.insert(.name) }
    }
    var label: String {
        didSet { providedFields.insert(.label) }
    }
    var summary: String {
        didSet { providedFields.insert(.summary) }
    }
    var address: String {
        didSet { providedFields.insert(.address) }
    }
    var city: String {
        didSet { providedFields.insert(.city) }
    }
    var state: String {
        didSet { providedFields.insert(.state) }
    }
    var zip: String {
        didSet { providedFields.insert(.zip) }
    }
    var countryCode: String {
        didSet { providedFields.insert(.countryCode) }
    }
    var website: String {
        didSet { providedFields.insert(.website) }
    }
    var email: String {
        didSet { providedFields.insert(.email) }
    }
    var phone: String {
        didSet { providedFields.insert(.phone) }
    }
    var socialProfiles: [ApplicantSocialProfileDraft] {
        didSet { providedFields.insert(.socialProfiles) }
    }
    var pictureData: Data?
    var pictureMimeType: String?
    var suggestedEmails: [String] = []
    init(
        name: String = "",
        label: String = "",
        summary: String = "",
        address: String = "",
        city: String = "",
        state: String = "",
        zip: String = "",
        countryCode: String = "",
        website: String = "",
        email: String = "",
        phone: String = "",
        socialProfiles: [ApplicantSocialProfileDraft] = [],
        pictureData: Data? = nil,
        pictureMimeType: String? = nil,
        suggestedEmails: [String] = []
    ) {
        self.name = name
        self.label = label
        self.summary = summary
        self.address = address
        self.city = city
        self.state = state
        self.zip = zip
        self.countryCode = countryCode
        self.website = website
        self.email = email
        self.phone = phone
        self.socialProfiles = socialProfiles
        self.pictureData = pictureData
        self.pictureMimeType = pictureMimeType
        // Only mark .picture as provided if we actually have picture data
        // This prevents apply(to:replaceMissing:false) from clearing existing photos
        var fields = Set(Field.allCases)
        if pictureData == nil {
            fields.remove(.picture)
        }
        self.providedFields = fields
        self.suggestedEmails = suggestedEmails.uniquedPreservingOrder()
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
        self.website = profile.websites
        self.email = profile.email
        self.phone = profile.phone
        self.socialProfiles = profile.profiles.map(ApplicantSocialProfileDraft.init(model:))
        self.pictureData = profile.pictureData
        self.pictureMimeType = profile.pictureMimeType
        // Only mark .picture as provided if we actually have picture data
        var fields = Set(Field.allCases)
        if profile.pictureData == nil {
            fields.remove(.picture)
        }
        self.providedFields = fields
        self.suggestedEmails = []
    }
    init(json: JSON) {
        self.providedFields = []
        let basics = json["basics"]
        let nameSource = basics != .null ? basics["name"] : json["name"]
        self.name = nameSource.stringValue
        if nameSource != .null { providedFields.insert(.name) }
        let labelSource = basics != .null ? basics["label"] : json["label"]
        self.label = labelSource.stringValue
        if labelSource != .null { providedFields.insert(.label) }
        let summarySource = basics != .null ? basics["summary"] : json["summary"]
        self.summary = summarySource.stringValue
        if summarySource != .null { providedFields.insert(.summary) }
        let locationJSON: JSON
        if basics != .null, basics["location"] != .null {
            locationJSON = basics["location"]
        } else {
            locationJSON = json["location"]
        }
        let addressSource = locationJSON["address"] != .null ? locationJSON["address"] : json["address"]
        self.address = addressSource.stringValue
        if addressSource != .null { providedFields.insert(.address) }
        let citySource = locationJSON["city"] != .null ? locationJSON["city"] : json["city"]
        self.city = citySource.stringValue
        if citySource != .null { providedFields.insert(.city) }
        let stateSources: [JSON] = [
            locationJSON["state"],
            locationJSON["region"],
            json["state"]
        ]
        if let stateSource = stateSources.first(where: { $0 != .null }) {
            self.state = stateSource.stringValue
            providedFields.insert(.state)
        } else {
            self.state = ""
        }
        let zipSources: [JSON] = [
            locationJSON["postalCode"],
            locationJSON["zip"],
            json["zip"]
        ]
        if let zipSource = zipSources.first(where: { $0 != .null }) {
            self.zip = zipSource.stringValue
            providedFields.insert(.zip)
        } else {
            self.zip = ""
        }
        let countrySource = locationJSON["countryCode"] != .null ? locationJSON["countryCode"] : json["country"]
        self.countryCode = countrySource.stringValue
        if countrySource != .null { providedFields.insert(.countryCode) }
        func firstString(from candidates: [JSON]) -> (String, Bool) {
            if let source = candidates.first(where: { $0 != .null }) {
                return (source.stringValue, true)
            }
            return ("", false)
        }
        let (websiteValue, websiteProvided) = firstString(from: [
            basics["url"],
            basics["website"],
            basics["websites"],
            json["url"],
            json["website"],
            json["websites"]
        ])
        self.website = websiteValue
        if websiteProvided { providedFields.insert(.website) }
        let contactEmailOptions = json["__contact_email_options"].arrayValue
            .compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.suggestedEmails = contactEmailOptions.uniquedPreservingOrder()
        let (emailValue, emailProvided) = firstString(from: [
            basics["email"],
            json["email"]
        ])
        self.email = emailValue
        if emailProvided { providedFields.insert(.email) }
        if !emailProvided, let firstSuggestion = suggestedEmails.first {
            self.email = firstSuggestion
        }
        let (phoneValue, phoneProvided) = firstString(from: [
            basics["phone"],
            json["phone"]
        ])
        self.phone = phoneValue
        if phoneProvided { providedFields.insert(.phone) }
        let profilesJSON: JSON
        if basics != .null, basics["profiles"] != .null {
            profilesJSON = basics["profiles"]
        } else {
            profilesJSON = json["profiles"]
        }
        let profileArray = profilesJSON.arrayValue
        self.socialProfiles = profileArray.map { value in
            ApplicantSocialProfileDraft(
                id: UUID(uuidString: value["id"].stringValue) ?? UUID(),
                network: value["network"].stringValue,
                username: value["username"].stringValue,
                url: value["url"].stringValue
            )
        }
        if profilesJSON != .null { providedFields.insert(.socialProfiles) }
        let imageJSON: JSON
        if basics != .null, basics["image"] != .null {
            imageJSON = basics["image"]
        } else {
            imageJSON = json["image"]
        }
        if let image = imageJSON.string, let data = Data(base64Encoded: image) {
            self.pictureData = data
            providedFields.insert(.picture)
            if basics != .null,
               let mime = basics["image_mime_type"].string ?? basics["imageMimeType"].string {
                self.pictureMimeType = mime
            } else {
                self.pictureMimeType = json["image_mime_type"].string
            }
            if pictureMimeType == nil {
                self.pictureMimeType = "image/png"
            }
        } else {
            self.pictureData = nil
            self.pictureMimeType = nil
        }
    }
    mutating func updatePicture(data: Data?, mimeType: String?) {
        pictureData = data
        pictureMimeType = data == nil ? nil : (mimeType ?? pictureMimeType ?? "image/png")
        providedFields.insert(.picture)
    }
    func merging(_ other: ApplicantProfileDraft) -> ApplicantProfileDraft {
        var merged = self
        merged.providedFields.formUnion(other.providedFields)
        if other.shouldUse(.name, isEmpty: other.name.isEmpty) { merged.name = other.name }
        if other.shouldUse(.label, isEmpty: other.label.isEmpty) { merged.label = other.label }
        if other.shouldUse(.summary, isEmpty: other.summary.isEmpty) { merged.summary = other.summary }
        if other.shouldUse(.address, isEmpty: other.address.isEmpty) { merged.address = other.address }
        if other.shouldUse(.city, isEmpty: other.city.isEmpty) { merged.city = other.city }
        if other.shouldUse(.state, isEmpty: other.state.isEmpty) { merged.state = other.state }
        if other.shouldUse(.zip, isEmpty: other.zip.isEmpty) { merged.zip = other.zip }
        if other.shouldUse(.countryCode, isEmpty: other.countryCode.isEmpty) { merged.countryCode = other.countryCode }
        if other.shouldUse(.website, isEmpty: other.website.isEmpty) { merged.website = other.website }
        if other.shouldUse(.email, isEmpty: other.email.isEmpty) { merged.email = other.email }
        if other.shouldUse(.phone, isEmpty: other.phone.isEmpty) { merged.phone = other.phone }
        if other.shouldUse(.socialProfiles, isEmpty: other.socialProfiles.isEmpty) {
            merged.socialProfiles = other.socialProfiles
        }
        if other.shouldUse(.picture, isEmpty: other.pictureData == nil) {
            merged.pictureData = other.pictureData
            merged.pictureMimeType = other.pictureMimeType
        }
        if !other.suggestedEmails.isEmpty {
            merged.suggestedEmails = (merged.suggestedEmails + other.suggestedEmails).uniquedPreservingOrder()
        }
        return merged
    }
    func apply(to profile: ApplicantProfile, replaceMissing: Bool = true) {
        if replaceMissing || shouldUse(.name, isEmpty: name.isEmpty) { profile.name = name }
        if replaceMissing || shouldUse(.label, isEmpty: label.isEmpty) { profile.label = label }
        if replaceMissing || shouldUse(.summary, isEmpty: summary.isEmpty) { profile.summary = summary }
        if replaceMissing || shouldUse(.address, isEmpty: address.isEmpty) { profile.address = address }
        if replaceMissing || shouldUse(.city, isEmpty: city.isEmpty) { profile.city = city }
        if replaceMissing || shouldUse(.state, isEmpty: state.isEmpty) { profile.state = state }
        if replaceMissing || shouldUse(.zip, isEmpty: zip.isEmpty) { profile.zip = zip }
        if replaceMissing || shouldUse(.countryCode, isEmpty: countryCode.isEmpty) { profile.countryCode = countryCode }
        if replaceMissing || shouldUse(.website, isEmpty: website.isEmpty) { profile.websites = website }
        if replaceMissing || shouldUse(.email, isEmpty: email.isEmpty) { profile.email = email }
        if replaceMissing || shouldUse(.phone, isEmpty: phone.isEmpty) { profile.phone = phone }
        if replaceMissing || shouldUse(.socialProfiles, isEmpty: socialProfiles.isEmpty) {
            profile.profiles = socialProfiles.map { $0.toModel() }
        }
        if replaceMissing || shouldUse(.picture, isEmpty: pictureData == nil) {
            profile.pictureData = pictureData
            profile.pictureMimeType = pictureMimeType
        }
    }
    func toJSON() -> JSON {
        var location: [String: Any] = [:]
        if providedFields.contains(.address) || !address.isEmpty { location["address"] = address }
        if providedFields.contains(.city) || !city.isEmpty { location["city"] = city }
        if providedFields.contains(.state) || !state.isEmpty { location["region"] = state }
        if providedFields.contains(.zip) || !zip.isEmpty { location["postalCode"] = zip }
        if providedFields.contains(.countryCode) || !countryCode.isEmpty { location["countryCode"] = countryCode }
        var payload: [String: Any] = [
            "name": name,
            "email": email,
            "phone": phone,
            "url": website
        ]
        if !location.isEmpty {
            payload["location"] = location
        }
        if providedFields.contains(.socialProfiles) || !socialProfiles.isEmpty {
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
        if payload["location"] == nil {
            payload["location"] = [:]
        }
        if !suggestedEmails.isEmpty {
            payload["__contact_email_options"] = JSON(suggestedEmails)
        }
        return JSON(payload)
    }
    func toSafeJSON() -> JSON {
        ApplicantProfileDraft.removeHiddenEmailOptions(from: toJSON())
    }
    static func removeHiddenEmailOptions(from json: JSON) -> JSON {
        var sanitized = json
        if var dictionary = sanitized.dictionaryObject {
            dictionary.removeValue(forKey: "__contact_email_options")
            sanitized = JSON(dictionary)
        } else if sanitized["__contact_email_options"] != .null {
            sanitized["__contact_email_options"] = .null
        }
        return sanitized
    }
    private func shouldUse(_ field: Field, isEmpty: Bool) -> Bool {
        providedFields.contains(field) || !isEmpty
    }
    var pictureImage: NSImage? {
        guard let pictureData else { return nil }
        return NSImage(data: pictureData)
    }
}
private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen: Set<Element> = []
        return self.filter { element in
            if seen.contains(element) {
                return false
            }
            seen.insert(element)
            return true
        }
    }
}
