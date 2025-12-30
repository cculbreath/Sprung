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
final class NetworkingContactStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
    }

    var allContacts: [NetworkingContact] {
        (try? modelContext.fetch(
            FetchDescriptor<NetworkingContact>(sortBy: [SortDescriptor(\.name)])
        )) ?? []
    }

    var needsAttention: [NetworkingContact] {
        allContacts.filter {
            $0.relationshipHealth == .needsAttention || $0.relationshipHealth == .decaying
        }
    }

    var hotContacts: [NetworkingContact] {
        allContacts.filter { $0.warmth == .hot }
    }

    func add(_ contact: NetworkingContact) {
        modelContext.insert(contact)
        saveContext()
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
        saveContext()
    }

    // MARK: - Warmth Management

    func updateWarmth(_ contact: NetworkingContact, to warmth: ContactWarmth) {
        contact.warmth = warmth
        contact.updatedAt = Date()
        saveContext()
    }

    /// Auto-decay warmth based on time since last contact
    func decayWarmthIfNeeded(_ contact: NetworkingContact) {
        guard let days = contact.daysSinceContact else { return }

        let newWarmth: ContactWarmth
        switch contact.warmth {
        case .hot:
            if days > 21 { newWarmth = .warm }
            else { return }
        case .warm:
            if days > 60 { newWarmth = .cold }
            else { return }
        case .cold:
            if days > 120 { newWarmth = .dormant }
            else { return }
        case .dormant:
            return
        }

        contact.warmth = newWarmth
        contact.updatedAt = Date()
        saveContext()
    }

    /// Update warmth for all contacts based on decay rules
    func updateAllWarmthLevels() {
        for contact in allContacts {
            decayWarmthIfNeeded(contact)
        }
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
