//
//  ContactsImportService.swift
//  Sprung
//
//  Imports applicant profile data from macOS Contacts ("Me" card).
//  Handles permission requests and draft building.
//

import Contacts
import Foundation

@MainActor
final class ContactsImportService {
    // MARK: - Public API

    /// Fetches the user's "Me" contact card and converts it to an ApplicantProfileDraft.
    /// - Throws: `ContactFetchError` if permission is denied, contact not found, or system error.
    func fetchMeCardAsDraft() async throws -> ApplicantProfileDraft {
        try await requestContactsAccess()

        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor
        ]

        let contact: CNContact
        do {
            contact = try store.unifiedMeContactWithKeys(toFetch: keys)
        } catch {
            if let cnError = error as? CNError, cnError.code == .recordDoesNotExist {
                throw ContactFetchError.notFound
            }
            throw ContactFetchError.system(error.localizedDescription)
        }

        Logger.debug("📇 Fetched Me card from Contacts", category: .ai)
        return buildDraft(from: contact)
    }

    // MARK: - Private Helpers

    private func requestContactsAccess() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CNContactStore().requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: ContactFetchError.system(error.localizedDescription))
                } else if granted {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ContactFetchError.permissionDenied)
                }
            }
        }
    }

    private func buildDraft(from contact: CNContact) -> ApplicantProfileDraft {
        var draft = ApplicantProfileDraft()

        // Name
        let fullName = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !fullName.isEmpty {
            draft.name = fullName
        }

        // Job title
        if !contact.jobTitle.isEmpty {
            draft.label = contact.jobTitle
        }

        // Organization
        if !contact.organizationName.isEmpty {
            draft.summary = "Current role at \(contact.organizationName)."
        }

        // Emails
        let emailValues = contact.emailAddresses.compactMap { ($0.value as String).trimmedNonEmpty }
        if !emailValues.isEmpty {
            draft.suggestedEmails = Array(Set(emailValues))
            if draft.email.isEmpty {
                draft.email = draft.suggestedEmails.first ?? ""
            }
        }

        // Phone
        if let phone = contact.phoneNumbers.first?.value.stringValue {
            draft.phone = phone
        }

        // Address
        if let postalAddress = contact.postalAddresses.first?.value {
            if let street = postalAddress.street.trimmedNonEmpty {
                draft.address = street
            }
            if let city = postalAddress.city.trimmedNonEmpty {
                draft.city = city
            }
            if let state = postalAddress.state.trimmedNonEmpty {
                draft.state = state
            }
            if let postalCode = postalAddress.postalCode.trimmedNonEmpty {
                draft.zip = postalCode
            }
            if let countryCode = postalAddress.isoCountryCode.trimmedNonEmpty {
                draft.countryCode = countryCode.uppercased()
            }
        }

        return draft
    }
}

// MARK: - Error Handling

enum ContactFetchError: Error {
    case permissionDenied
    case notFound
    case system(String)

    var message: String {
        switch self {
        case .permissionDenied:
            return "Sprung does not have permission to access your contacts."
        case .notFound:
            return "We couldn't find a 'Me' contact on this Mac."
        case .system(let description):
            return "Unable to access contacts: \(description)"
        }
    }
}
