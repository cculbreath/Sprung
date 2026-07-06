//
//  AddContactSheet.swift
//  Sprung
//
//  Form sheet for manually adding a networking contact.
//

import SwiftUI

struct AddContactSheet: View {
    let store: NetworkingContactStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var company = ""
    @State private var role = ""
    @State private var channel: ContactChannelKind = .email
    @State private var channelValue = ""
    @State private var warmth: ContactWarmth = .warm

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Add Contact")
                    .font(.headline)

                Spacer()

                Button("Add") {
                    saveContact()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            // Form
            Form {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("Company", text: $company)
                    .textFieldStyle(.roundedBorder)

                TextField("Role", text: $role)
                    .textFieldStyle(.roundedBorder)

                Picker("Contact Via", selection: $channel) {
                    ForEach(ContactChannelKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }

                TextField(channel.placeholder, text: $channelValue)
                    .textFieldStyle(.roundedBorder)

                Picker("Warmth", selection: $warmth) {
                    ForEach(ContactWarmth.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
            }
            .padding()
        }
        .frame(width: 400, height: 360)
    }

    private func saveContact() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let trimmedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = NetworkingContact(
            name: trimmedName,
            company: trimmedCompany.isEmpty ? nil : trimmedCompany
        )

        let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.title = trimmedRole.isEmpty ? nil : trimmedRole
        contact.warmth = warmth
        // A manually added contact was just reached — start the relationship
        // clock now instead of leaving health frozen at "New" forever.
        contact.lastContactAt = Date()

        let trimmedChannelValue = channelValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedChannelValue.isEmpty {
            switch channel {
            case .email: contact.email = trimmedChannelValue
            case .phone: contact.phone = trimmedChannelValue
            case .linkedIn: contact.linkedInUrl = trimmedChannelValue
            case .other: contact.otherContactInfo = trimmedChannelValue
            }
        }

        store.add(contact)
        dismiss()
    }
}

/// UI-only grouping of the contact's primary reach-out channel; the value is
/// written into the matching `NetworkingContact` field on save (the model has
/// no single unified "channel" field).
private enum ContactChannelKind: String, CaseIterable, Identifiable {
    case email = "Email"
    case phone = "Phone"
    case linkedIn = "LinkedIn"
    case other = "Other"

    var id: String { rawValue }

    var placeholder: String {
        switch self {
        case .email: return "Email address"
        case .phone: return "Phone number"
        case .linkedIn: return "LinkedIn URL"
        case .other: return "Contact info"
        }
    }
}
