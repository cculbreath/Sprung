//
//  ContactsView.swift
//  Sprung
//
//  Networking contacts view for managing professional relationships.
//  Displays contacts grouped by status and warmth level.
//

import SwiftUI

struct ContactsView: View {
    let coordinator: SearchOpsCoordinator

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Networking Contacts")
                .font(.title)

            Text("Track professional contacts, relationship warmth,\nand follow-up actions.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            if coordinator.contactStore.allContacts.isEmpty {
                Button("Add Contact") {
                    // TODO: Show add contact sheet
                }
                .buttonStyle(.borderedProminent)
            } else {
                List {
                    if !coordinator.contactStore.needsAttention.isEmpty {
                        Section("Needs Attention") {
                            ForEach(coordinator.contactStore.needsAttention) { contact in
                                ContactRowView(contact: contact)
                            }
                        }
                    }

                    if !coordinator.contactStore.hotContacts.isEmpty {
                        Section("Hot Contacts") {
                            ForEach(coordinator.contactStore.hotContacts) { contact in
                                ContactRowView(contact: contact)
                            }
                        }
                    }

                    Section("All Contacts") {
                        ForEach(coordinator.contactStore.allContacts) { contact in
                            ContactRowView(contact: contact)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Contacts")
    }
}

struct ContactRowView: View {
    let contact: NetworkingContact

    var body: some View {
        HStack {
            Image(systemName: contact.relationshipHealth.icon)
                .foregroundStyle(healthColor(contact.relationshipHealth))

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName)
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
