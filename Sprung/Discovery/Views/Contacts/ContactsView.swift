//
//  ContactsView.swift
//  Sprung
//
//  Networking contacts view for managing professional relationships.
//  Displays contacts grouped by status and warmth level.
//

import SwiftUI

struct ContactsView: View {
    let coordinator: DiscoveryCoordinator

    @State private var showingAddSheet = false
    @State private var selectedContact: NetworkingContact?
    @State private var contactPendingDelete: NetworkingContact?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Networking Contacts")
                        .font(.headline)
                    Text("Professional contacts and relationship warmth")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Contact", systemImage: "plus")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.windowBackgroundColor))
            .overlay(alignment: .bottom) {
                Divider()
            }

            if coordinator.contactStore.allContacts.isEmpty {
                emptyStateView
            } else {
                contactList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("")
        .sheet(isPresented: $showingAddSheet) {
            AddContactSheet(store: coordinator.contactStore)
        }
        .sheet(item: $selectedContact) { contact in
            ContactDetailSheet(contact: contact, store: coordinator.contactStore)
        }
        .confirmationDialog(
            "Delete \(contactPendingDelete?.name ?? "contact")?",
            isPresented: Binding(
                get: { contactPendingDelete != nil },
                set: { if !$0 { contactPendingDelete = nil } }
            ),
            presenting: contactPendingDelete
        ) { contact in
            Button("Delete", role: .destructive) {
                coordinator.contactStore.delete(contact)
                contactPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                contactPendingDelete = nil
            }
        } message: { _ in
            Text("This removes the contact and their relationship history.")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "teletype.answer.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Contacts Yet")
                .font(.title)

            Text("Track professional contacts, relationship warmth,\nand follow-up actions.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            Button("Add Contact") {
                showingAddSheet = true
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var contactList: some View {
        List {
            if !coordinator.contactStore.needsAttention.isEmpty {
                Section("Needs Attention") {
                    ForEach(coordinator.contactStore.needsAttention) { contact in
                        row(for: contact)
                    }
                }
            }

            if !coordinator.contactStore.hotContacts.isEmpty {
                Section("Hot Contacts") {
                    ForEach(coordinator.contactStore.hotContacts) { contact in
                        row(for: contact)
                    }
                }
            }

            Section("All Contacts") {
                ForEach(coordinator.contactStore.allContacts) { contact in
                    row(for: contact)
                }
            }
        }
        .scrollEdgeEffect()
    }

    private func row(for contact: NetworkingContact) -> some View {
        ContactRowView(contact: contact)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedContact = contact
            }
            .contextMenu {
                Button {
                    coordinator.contactStore.recordInteraction(contact, type: "Marked contacted")
                } label: {
                    Label("Mark Contacted", systemImage: "checkmark.circle")
                }

                Button(role: .destructive) {
                    contactPendingDelete = contact
                } label: {
                    Label("Delete Contact", systemImage: "trash")
                }
            }
    }
}

struct ContactRowView: View {
    let contact: NetworkingContact

    var body: some View {
        HStack {
            Image(systemName: contact.relationshipHealth.icon)
                .foregroundStyle(healthColor(contact.relationshipHealth))

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .font(.headline)
                if let info = contact.companyAndTitle {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(contact.warmth.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(warmthColor(contact.warmth).opacity(0.2))
                .cornerRadius(4)

            if let days = contact.daysSinceContact {
                Text("\(days)d")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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

    private func warmthColor(_ warmth: ContactWarmth) -> Color {
        switch warmth {
        case .hot: return .red
        case .warm: return .orange
        case .cold: return .blue
        case .dormant: return .gray
        }
    }
}
