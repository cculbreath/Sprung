//
//  NetworkingContactStoreTests.swift
//  SprungTests
//
//  Pins the contact CRM verbs behind the Contacts UI: recordInteraction
//  advances the relationship clock (clearing the needs-attention nag),
//  updateWarmth re-buckets relationship health, and delete removes the
//  contact. Also pins the health contract AddContactSheet relies on: a
//  contact with lastContactAt set starts .healthy (and can decay), while
//  one without stays .new and is never nagged.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class NetworkingContactStoreTests: InMemoryStoreCase {

    // MARK: - Helpers

    private func makeStore() -> NetworkingContactStore {
        NetworkingContactStore(context: context)
    }

    private func makeContact(
        name: String = "Alice Chen",
        warmth: ContactWarmth = .warm,
        lastContactDaysAgo: Int? = nil
    ) -> NetworkingContact {
        let contact = NetworkingContact(name: name, company: "Acme")
        contact.warmth = warmth
        if let daysAgo = lastContactDaysAgo {
            contact.lastContactAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())
        }
        return contact
    }

    // MARK: - recordInteraction

    func testRecordInteractionAdvancesLastContactAndClearsAttentionNag() throws {
        let store = makeStore()
        let contact = makeContact(warmth: .warm, lastContactDaysAgo: 45)
        store.add(contact)

        // 45 days on a warm contact = "Needs Attention" — the DailyView nag.
        XCTAssertEqual(contact.relationshipHealth, .needsAttention)
        XCTAssertTrue(store.needsAttention.contains { $0.id == contact.id })

        store.recordInteraction(contact, type: "Follow Up")

        let lastContact = try XCTUnwrap(contact.lastContactAt)
        XCTAssertEqual(lastContact.timeIntervalSinceNow, 0, accuracy: 5)
        XCTAssertEqual(contact.lastContactType, "Follow Up")
        XCTAssertEqual(contact.totalInteractions, 1)
        XCTAssertEqual(contact.relationshipHealth, .healthy)
        XCTAssertFalse(store.needsAttention.contains { $0.id == contact.id })
    }

    func testRecordInteractionClearsDecayingState() {
        let store = makeStore()
        let contact = makeContact(warmth: .hot, lastContactDaysAgo: 30)
        store.add(contact)

        // A hot contact untouched for 30 days has fully decayed.
        XCTAssertEqual(contact.relationshipHealth, .decaying)
        XCTAssertTrue(store.needsAttention.contains { $0.id == contact.id })

        store.recordInteraction(contact, type: "Marked contacted")

        XCTAssertEqual(contact.relationshipHealth, .healthy)
        XCTAssertFalse(store.needsAttention.contains { $0.id == contact.id })
    }

    // MARK: - updateWarmth

    func testUpdateWarmthRebucketsRelationshipHealth() {
        let store = makeStore()
        let contact = makeContact(warmth: .warm, lastContactDaysAgo: 25)
        store.add(contact)

        // 25 days is fine for a warm contact...
        XCTAssertEqual(contact.relationshipHealth, .healthy)
        XCTAssertFalse(store.needsAttention.contains { $0.id == contact.id })

        store.updateWarmth(contact, to: .hot)

        // ...but a hot contact needs touching within 21 days.
        XCTAssertEqual(contact.warmth, .hot)
        XCTAssertEqual(contact.relationshipHealth, .decaying)
        XCTAssertTrue(store.needsAttention.contains { $0.id == contact.id })
    }

    // MARK: - Health contract for newly added contacts

    func testContactWithLastContactSetStartsHealthyNotNew() {
        // AddContactSheet sets lastContactAt on creation: a manually added
        // contact was just reached, so it starts .healthy and can decay —
        // instead of being frozen at .new forever.
        let store = makeStore()
        let contact = makeContact(warmth: .warm, lastContactDaysAgo: 0)
        store.add(contact)

        XCTAssertEqual(contact.relationshipHealth, .healthy)
        XCTAssertFalse(store.needsAttention.contains { $0.id == contact.id })
    }

    func testContactWithoutLastContactIsNewAndNeverNagged() {
        // Real contract: with no recorded contact the health is .new, which the
        // needs-attention predicate excludes — the nag only starts once the
        // relationship clock has been started.
        let store = makeStore()
        let contact = makeContact(warmth: .warm, lastContactDaysAgo: nil)
        store.add(contact)

        XCTAssertEqual(contact.relationshipHealth, .new)
        XCTAssertFalse(store.needsAttention.contains { $0.id == contact.id })
    }

    func testColdContactIsDormantNotNagged() {
        // Real contract: cold/dormant warmth maps to .dormant regardless of
        // elapsed time, so those contacts never appear in needsAttention.
        let store = makeStore()
        let contact = makeContact(warmth: .cold, lastContactDaysAgo: 200)
        store.add(contact)

        XCTAssertEqual(contact.relationshipHealth, .dormant)
        XCTAssertFalse(store.needsAttention.contains { $0.id == contact.id })
    }

    // MARK: - Delete

    func testDeleteRemovesContact() throws {
        let store = makeStore()
        let contact = makeContact()
        store.add(contact)
        XCTAssertEqual(store.allContacts.count, 1)

        store.delete(contact)

        XCTAssertTrue(store.allContacts.isEmpty)
        XCTAssertTrue(try fetchAll(NetworkingContact.self).isEmpty)
    }
}
