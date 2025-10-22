import Contacts
import Foundation
import SwiftyJSON

enum SystemContactsFetcherError: Error, LocalizedError {
    case accessDenied
    case contactUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to Contacts was denied."
        case .contactUnavailable:
            return "Unable to locate your contact card."
        }
    }
}

@MainActor
enum SystemContactsFetcher {
    static func fetchApplicantProfile(requestedFields: [String]) async throws -> JSON {
        let store = CNContactStore()

        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            try await store.requestAccess(for: .contacts)
        }

        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            throw SystemContactsFetcherError.accessDenied
        }

        let keys = contactKeys(for: requestedFields)
        let contacts = try store.unifiedContacts(
            matching: CNContact.predicateForContactsInContainer(withIdentifier: store.defaultContainerIdentifier()),
            keysToFetch: keys
        )
        guard let contact = contacts.first(where: { $0.contactType == .person }) ?? contacts.first else {
            throw SystemContactsFetcherError.contactUnavailable
        }

        return buildJSON(from: contact)
    }

    private static func contactKeys(for requestedFields: [String]) -> [CNKeyDescriptor] {
        var descriptors: [CNKeyDescriptor] = [
            CNContactGivenNameKey as NSString,
            CNContactFamilyNameKey as NSString,
            CNContactMiddleNameKey as NSString,
            CNContactJobTitleKey as NSString,
            CNContactOrganizationNameKey as NSString,
            CNContactEmailAddressesKey as NSString,
            CNContactPhoneNumbersKey as NSString,
            CNContactPostalAddressesKey as NSString,
            CNContactUrlAddressesKey as NSString,
            CNContactImageDataKey as NSString
        ]

        if requestedFields.contains(where: { $0.lowercased() == "nickname" }) {
            descriptors.append(CNContactNicknameKey as NSString)
        }

        return descriptors
    }

    private static func buildJSON(from contact: CNContact) -> JSON {
        let nameComponents = PersonNameComponents(
            givenName: contact.givenName,
            middleName: contact.middleName,
            familyName: contact.familyName
        )
        let formatter = PersonNameComponentsFormatter()
        let fullName = formatter.string(from: nameComponents).trimmingCharacters(in: .whitespacesAndNewlines)

        var payload: [String: Any] = [:]
        if !fullName.isEmpty { payload["name"] = fullName }
        if !contact.jobTitle.isEmpty { payload["label"] = contact.jobTitle }
        if !contact.organizationName.isEmpty {
            payload["company"] = contact.organizationName
        }
        if let email = contact.emailAddresses.first?.value as String? {
            payload["email"] = email
        }
        if let phone = contact.phoneNumbers.first?.value.stringValue {
            payload["phone"] = phone
        }

        if let postal = contact.postalAddresses.first?.value {
            var location: [String: Any] = [:]
            if !postal.street.isEmpty { location["address"] = postal.street }
            if !postal.city.isEmpty { location["city"] = postal.city }
            if !postal.state.isEmpty { location["region"] = postal.state }
            if !postal.postalCode.isEmpty { location["postalCode"] = postal.postalCode }
            if !postal.country.isEmpty { location["countryCode"] = postal.isoCountryCode }
            payload["location"] = location
        }

        if let url = contact.urlAddresses.first?.value as String? {
            payload["website"] = url
        }

        if let imageData = contact.imageData, !imageData.isEmpty {
            payload["image"] = imageData.base64EncodedString()
            payload["image_mime_type"] = "image/jpeg"
        }

        return JSON(payload)
    }
}
