//
//  ContactDetailSheet.swift
//  Sprung
//
//  Detail sheet for a networking contact: view/edit fields, mark contacted
//  (advances the relationship clock and clears the attention nag), reach out
//  via email/LinkedIn, and delete the contact.
//

import SwiftUI

struct ContactDetailSheet: View {
    let contact: NetworkingContact
    let store: NetworkingContactStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var company: String
    @State private var title: String
    @State private var email: String
    @State private var phone: String
    @State private var linkedInUrl: String
    @State private var otherContactInfo: String
    @State private var relationship: RelationshipType
    @State private var warmth: ContactWarmth
    @State private var notes: String
    @State private var showingDeleteConfirmation = false

    init(contact: NetworkingContact, store: NetworkingContactStore) {
        self.contact = contact
        self.store = store
        _name = State(initialValue: contact.name)
        _company = State(initialValue: contact.company ?? "")
        _title = State(initialValue: contact.title ?? "")
        _email = State(initialValue: contact.email ?? "")
        _phone = State(initialValue: contact.phone ?? "")
        _linkedInUrl = State(initialValue: contact.linkedInUrl ?? "")
        _otherContactInfo = State(initialValue: contact.otherContactInfo ?? "")
        _relationship = State(initialValue: contact.relationship)
        _warmth = State(initialValue: contact.warmth)
        _notes = State(initialValue: contact.notes)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Contact")
                    .font(.headline)

                Spacer()

                Button("Save") {
                    saveContact()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            statusSection
                .padding()

            Divider()

            Form {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("Company", text: $company)
                    .textFieldStyle(.roundedBorder)

                TextField("Role", text: $title)
                    .textFieldStyle(.roundedBorder)

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)

                TextField("Phone", text: $phone)
                    .textFieldStyle(.roundedBorder)

                TextField("LinkedIn URL", text: $linkedInUrl)
                    .textFieldStyle(.roundedBorder)

                TextField("Other contact info", text: $otherContactInfo)
                    .textFieldStyle(.roundedBorder)

                Picker("Relationship", selection: $relationship) {
                    ForEach(RelationshipType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                Picker("Warmth", selection: $warmth) {
                    ForEach(ContactWarmth.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Contact", systemImage: "trash")
                }

                Spacer()
            }
            .padding()
        }
        .frame(width: 440, height: 640)
        .confirmationDialog(
            "Delete \(contact.name)?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                store.delete(contact)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the contact and their relationship history.")
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: contact.relationshipHealth.icon)
                    .foregroundStyle(healthColor(contact.relationshipHealth))
                Text(contact.relationshipHealth.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(lastContactDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let metAt = contact.metAt {
                Text("Met at \(metAt)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    store.recordInteraction(contact, type: "Marked contacted")
                } label: {
                    Label("Mark Contacted", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .help("Record that you reached out — resets the attention timer")

                if let mailURL = mailURL {
                    Button {
                        NSWorkspace.shared.open(mailURL)
                    } label: {
                        Label("Email", systemImage: "envelope")
                    }
                }

                if let profileURL = linkedInURL {
                    Button {
                        NSWorkspace.shared.open(profileURL)
                    } label: {
                        Label("LinkedIn", systemImage: "link")
                    }
                }

                Spacer()
            }
        }
    }

    private var lastContactDescription: String {
        guard let days = contact.daysSinceContact else { return "No contact recorded" }
        if days <= 0 { return "Contacted today" }
        return "Last contact: \(days)d ago"
    }

    private var mailURL: URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "mailto:\(trimmed)")
    }

    private var linkedInURL: URL? {
        let trimmed = linkedInUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else { return nil }
        return url
    }

    private func healthColor(_ health: RelationshipHealth) -> Color {
        switch health {
        case .healthy: return .green
        case .needsAttention: return .orange
        case .decaying: return .red
        case .dormant: return .gray
        case .new: return .blue
        }
    }

    // MARK: - Save

    private func saveContact() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        contact.name = trimmedName
        contact.company = nilIfEmpty(company)
        contact.title = nilIfEmpty(title)
        contact.email = nilIfEmpty(email)
        contact.phone = nilIfEmpty(phone)
        contact.linkedInUrl = nilIfEmpty(linkedInUrl)
        contact.otherContactInfo = nilIfEmpty(otherContactInfo)
        contact.relationship = relationship
        contact.notes = notes
        contact.updatedAt = Date()

        if contact.warmth != warmth {
            store.updateWarmth(contact, to: warmth)
        } else {
            store.update(contact)
        }
        dismiss()
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
