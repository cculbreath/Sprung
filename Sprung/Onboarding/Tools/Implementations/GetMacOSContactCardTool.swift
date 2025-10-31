//
//  GetMacOSContactCardTool.swift
//  Sprung
//
//  Imports the user's macOS contact card using Contacts.framework.
//

import Contacts
import CryptoKit
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetMacOSContactCardTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Fetch the user's macOS contact card.",
            properties: [
                "cardType": JSONSchema(
                    type: .string,
                    description: "Which contact card to fetch.",
                    enum: ["me", "specific"]
                )
            ],
            required: [],
            additionalProperties: false
        )
    }()

    var name: String { "get_macos_contact_card" }
    var description: String { "Fetch the macOS 'Me' contact card for the current user." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let request = try ContactCardRequest(json: params)

        guard request.cardType == .me else {
            return .error(.executionFailed("Fetching specific contacts is not implemented yet."))
        }

        do {
            let contact = try await fetchMeCard()
            let response = try makeResponse(from: contact)
            return .immediate(response)
        } catch ContactError.denied {
            var response = JSON()
            response["status"].string = "permission_denied"
            return .immediate(response)
        } catch ContactError.notFound {
            var response = JSON()
            response["status"].string = "not_found"
            return .immediate(response)
        } catch {
            return .error(.executionFailed("Failed to fetch contact card: \(error.localizedDescription)"))
        }
    }
}

private enum ContactError: Error {
    case denied
    case notFound
    case other(Error)
}

private struct ContactCardRequest {
    enum CardType: String {
        case me
        case specific
    }

    let cardType: CardType

    init(json: JSON) throws {
        if let explicit = json["cardType"].string?.lowercased() {
            guard let type = CardType(rawValue: explicit) else {
                throw ToolError.invalidParameters("cardType must be one of ['me', 'specific']")
            }
            cardType = type
        } else {
            cardType = .me
        }
    }
}

private func requestContactsAccess() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        CNContactStore().requestAccess(for: .contacts) { granted, error in
            if let error {
                continuation.resume(throwing: ContactError.other(error))
            } else if granted {
                continuation.resume()
            } else {
                continuation.resume(throwing: ContactError.denied)
            }
        }
    }
}

private func fetchMeCard() async throws -> CNContact {
    try await requestContactsAccess()

    let store = CNContactStore()
    let keys: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor
    ]

    do {
        return try store.unifiedMeContactWithKeys(toFetch: keys)
    } catch {
        if let cnError = error as? CNError, cnError.code == .recordDoesNotExist {
            throw ContactError.notFound
        }
        throw ContactError.other(error)
    }
}

private func makeResponse(from contact: CNContact) throws -> JSON {
    var response = JSON()
    var contactJSON = JSON()

    contactJSON["name"]["given"].string = contact.givenName
    contactJSON["name"]["family"].string = contact.familyName

    let emailArray = contact.emailAddresses.map { labeledValue -> JSON in
        var entry = JSON()
        entry["label"].string = CNLabeledValue<NSString>.localizedString(forLabel: labeledValue.label ?? "")
        entry["value"].string = labeledValue.value as String
        return entry
    }
    contactJSON["email"] = JSON(emailArray)

    let phoneArray = contact.phoneNumbers.map { labeledValue -> JSON in
        var entry = JSON()
        entry["label"].string = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: labeledValue.label ?? "")
        entry["value"].string = labeledValue.value.stringValue
        return entry
    }
    contactJSON["phone"] = JSON(phoneArray)

    if !contact.organizationName.isEmpty {
        contactJSON["organization"].string = contact.organizationName
    }
    if !contact.jobTitle.isEmpty {
        contactJSON["jobTitle"].string = contact.jobTitle
    }

    response["contact"] = contactJSON
    response["status"].string = "fetched"
    response["artifact_record"] = try makeArtifactRecord(from: contact, contactJSON: contactJSON)
    return response
}

private func makeArtifactRecord(from contact: CNContact, contactJSON: JSON) throws -> JSON {
    let data = try CNContactVCardSerialization.data(with: [contact])
    let filename: String
    if contact.givenName.isEmpty && contact.familyName.isEmpty {
        filename = "macos-contact.vcf"
    } else {
        let sanitized = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
        filename = sanitized.isEmpty ? "macos-contact.vcf" : "\(sanitized).vcf"
    }

    let sha256 = sha256Hex(for: data)
    let vcardText = String(data: data, encoding: .utf8) ?? ""

    var extractedPayload = JSON()
    extractedPayload["source"].string = "macos_contacts"
    extractedPayload["contact"] = contactJSON
    if !vcardText.isEmpty {
        extractedPayload["vcard"].string = vcardText
    }

    var artifact = JSON()
    artifact["id"].string = UUID().uuidString
    artifact["filename"].string = filename
    artifact["content_type"].string = "text/vcard"
    artifact["size_bytes"].int = data.count
    artifact["sha256"].string = sha256
    artifact["extracted_content"].string = extractedPayload.rawString(options: [.sortedKeys]) ?? "{}"

    artifact["metadata"]["purpose"].string = "applicant_profile_contact_card"
    artifact["metadata"]["source"].string = "macos_contacts"
    artifact["metadata"]["source_filename"].string = filename
    artifact["metadata"]["character_count"].int = vcardText.count
    artifact["metadata"]["inline_base64"].string = data.base64EncodedString()

    return artifact
}

private func sha256Hex(for data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
