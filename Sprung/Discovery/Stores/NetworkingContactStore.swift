//
//  NetworkingContactStore.swift
//  Sprung
//
//  Store for managing networking contacts.
//

import SwiftData
import Foundation

@Observable
@MainActor
final class NetworkingContactStore: EntityStore {
    typealias Entity = NetworkingContact

    unowned let modelContext: ModelContext

    /// `@Observable` refresh counter; bumped by EntityStore mutations so SwiftUI
    /// views reading the fetched collections re-render on insert/delete/update.
    var changeVersion: Int = 0

    init(context: ModelContext) {
        modelContext = context
    }

    var allContacts: [NetworkingContact] {
        fetchAll(sortBy: [SortDescriptor(\.name)])
    }

    var needsAttention: [NetworkingContact] {
        allContacts.filter {
            $0.relationshipHealth == .needsAttention || $0.relationshipHealth == .decaying
        }
    }

    var hotContacts: [NetworkingContact] {
        allContacts.filter { $0.warmth == .hot }
    }

    func contact(byId id: UUID) -> NetworkingContact? {
        allContacts.first { $0.id == id }
    }

    // MARK: - Interaction Recording

    func recordInteraction(_ contact: NetworkingContact, type: String) {
        contact.lastContactAt = Date()
        contact.lastContactType = type
        contact.totalInteractions += 1
        contact.updatedAt = Date()
        update(contact)
    }

    // MARK: - Warmth Management

    func updateWarmth(_ contact: NetworkingContact, to warmth: ContactWarmth) {
        contact.warmth = warmth
        contact.updatedAt = Date()
        update(contact)
    }

    /// Contacts added this week
    var thisWeeksNewContacts: [NetworkingContact] {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()

        return allContacts.filter { $0.createdAt >= weekStart }
    }
}
