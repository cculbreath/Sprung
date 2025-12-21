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

    var activeContacts: [NetworkingContact] {
        allContacts.filter { $0.warmth != .dormant }
    }

    var needsAttention: [NetworkingContact] {
        allContacts.filter {
            $0.relationshipHealth == .needsAttention || $0.relationshipHealth == .decaying
        }
    }

    var hotContacts: [NetworkingContact] {
        allContacts.filter { $0.warmth == .hot }
    }

    var warmContacts: [NetworkingContact] {
        allContacts.filter { $0.warmth == .warm }
    }

    var coldContacts: [NetworkingContact] {
        allContacts.filter { $0.warmth == .cold }
    }

    var dormantContacts: [NetworkingContact] {
        allContacts.filter { $0.warmth == .dormant }
    }

    var atTargetCompanies: [NetworkingContact] {
        allContacts.filter { $0.isAtTargetCompany }
    }

    var recruiters: [NetworkingContact] {
        allContacts.filter { $0.isRecruiter }
    }

    var hiringManagers: [NetworkingContact] {
        allContacts.filter { $0.isHiringManager }
    }

    var contactsWhoOfferedHelp: [NetworkingContact] {
        allContacts.filter { $0.hasOfferedToHelp }
    }

    func add(_ contact: NetworkingContact) {
        modelContext.insert(contact)
        saveContext()
    }

    func update(_ contact: NetworkingContact) {
        contact.updatedAt = Date()
        saveContext()
    }

    func delete(_ contact: NetworkingContact) {
        modelContext.delete(contact)
        saveContext()
    }

    func contact(byId id: UUID) -> NetworkingContact? {
        allContacts.first { $0.id == id }
    }

    func contacts(byCompany company: String) -> [NetworkingContact] {
        allContacts.filter { $0.company?.lowercased() == company.lowercased() }
    }

    func contacts(withTag tag: String) -> [NetworkingContact] {
        allContacts.filter { $0.tags.contains(tag) }
    }

    func contacts(fromEvent eventId: UUID) -> [NetworkingContact] {
        allContacts.filter { $0.metAtEventId == eventId }
    }

    // MARK: - Interaction Recording

    func recordInteraction(_ contact: NetworkingContact, type: String) {
        contact.lastContactAt = Date()
        contact.lastContactType = type
        contact.totalInteractions += 1
        contact.updatedAt = Date()
        saveContext()
    }

    func setNextAction(_ contact: NetworkingContact, action: String, date: Date?) {
        contact.nextAction = action
        contact.nextActionAt = date
        contact.updatedAt = Date()
        saveContext()
    }

    func clearNextAction(_ contact: NetworkingContact) {
        contact.nextAction = nil
        contact.nextActionAt = nil
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

    // MARK: - Statistics

    var totalContactCount: Int {
        allContacts.count
    }

    var activeContactCount: Int {
        activeContacts.count
    }

    var contactsByWarmth: [ContactWarmth: Int] {
        Dictionary(grouping: allContacts) { $0.warmth }
            .mapValues { $0.count }
    }

    var contactsByRelationship: [RelationshipType: Int] {
        Dictionary(grouping: allContacts) { $0.relationship }
            .mapValues { $0.count }
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
