//
//  RelationshipHealthService.swift
//  Sprung
//
//  Service for managing contact relationship health and warmth decay.
//  Provides automated warmth updates and follow-up reminders.
//

import Foundation

/// Service for managing relationship health across networking contacts
@Observable
@MainActor
final class RelationshipHealthService {

    // MARK: - Dependencies

    private let contactStore: NetworkingContactStore
    private let interactionStore: NetworkingInteractionStore

    // MARK: - Configuration

    /// Days until hot contacts start decaying
    private let hotDecayThreshold = 21

    /// Days until warm contacts start decaying
    private let warmDecayThreshold = 60

    /// Days until cold contacts become dormant
    private let coldDecayThreshold = 120

    // MARK: - Computed Properties

    /// Contacts that need immediate attention (decaying or overdue follow-ups)
    var urgentContacts: [NetworkingContact] {
        contactStore.allContacts.filter { contact in
            contact.relationshipHealth == .decaying ||
            hasOverdueFollowUp(for: contact)
        }
    }

    /// Contacts that should be reached out to soon
    var suggestedOutreach: [NetworkingContact] {
        contactStore.allContacts
            .filter { $0.relationshipHealth == .needsAttention }
            .sorted { ($0.daysSinceContact ?? 999) > ($1.daysSinceContact ?? 999) }
    }

    /// Hot contacts at risk of cooling down
    var hotContactsAtRisk: [NetworkingContact] {
        contactStore.hotContacts.filter { contact in
            guard let days = contact.daysSinceContact else { return false }
            return days >= 14 && days < hotDecayThreshold
        }
    }

    // MARK: - Initialization

    init(contactStore: NetworkingContactStore, interactionStore: NetworkingInteractionStore) {
        self.contactStore = contactStore
        self.interactionStore = interactionStore
    }

    // MARK: - Warmth Management

    /// Update warmth levels for all contacts based on time since last contact
    func updateAllWarmthLevels() {
        for contact in contactStore.allContacts {
            updateWarmthIfNeeded(contact)
        }
        Logger.info("🌡️ Updated warmth levels for \(contactStore.allContacts.count) contacts", category: .ai)
    }

    /// Update warmth for a specific contact if decay threshold reached
    func updateWarmthIfNeeded(_ contact: NetworkingContact) {
        guard let days = contact.daysSinceContact else { return }

        let newWarmth: ContactWarmth?

        switch contact.warmth {
        case .hot:
            if days > hotDecayThreshold {
                newWarmth = .warm
            } else {
                newWarmth = nil
            }
        case .warm:
            if days > warmDecayThreshold {
                newWarmth = .cold
            } else {
                newWarmth = nil
            }
        case .cold:
            if days > coldDecayThreshold {
                newWarmth = .dormant
            } else {
                newWarmth = nil
            }
        case .dormant:
            newWarmth = nil
        }

        if let newWarmth = newWarmth {
            contactStore.updateWarmth(contact, to: newWarmth)
            Logger.debug("🌡️ Contact \(contact.displayName) warmth decayed to \(newWarmth.rawValue)", category: .ai)
        }
    }

    /// Upgrade warmth based on positive interaction
    func upgradeWarmth(_ contact: NetworkingContact, reason: WarmthUpgradeReason) {
        let newWarmth: ContactWarmth

        switch reason {
        case .hadMeeting, .receivedReferral, .offeredHelp:
            newWarmth = .hot
        case .hadConversation, .respondedPositively:
            switch contact.warmth {
            case .dormant: newWarmth = .cold
            case .cold: newWarmth = .warm
            case .warm, .hot: newWarmth = .hot
            }
        case .sentMessage:
            switch contact.warmth {
            case .dormant: newWarmth = .cold
            case .cold, .warm, .hot: newWarmth = contact.warmth
            }
        }

        if newWarmth != contact.warmth {
            contactStore.updateWarmth(contact, to: newWarmth)
            Logger.info("🌡️ Contact \(contact.displayName) warmth upgraded to \(newWarmth.rawValue)", category: .ai)
        }
    }

    // MARK: - Follow-up Management

    /// Check if contact has overdue follow-ups
    func hasOverdueFollowUp(for contact: NetworkingContact) -> Bool {
        interactionStore.overdueFollowUps.contains { $0.contactId == contact.id }
    }

    /// Get pending follow-ups for a contact
    func pendingFollowUps(for contact: NetworkingContact) -> [NetworkingInteraction] {
        interactionStore.pendingFollowUps.filter { $0.contactId == contact.id }
    }

    /// Get suggested follow-up action for a contact
    func suggestedFollowUpAction(for contact: NetworkingContact) -> SuggestedFollowUp? {
        guard let days = contact.daysSinceContact else {
            // New contact - suggest initial follow-up
            return SuggestedFollowUp(
                contact: contact,
                action: "Send introduction message",
                urgency: .medium,
                reason: "New contact - establish connection"
            )
        }

        // Check for pending follow-ups first
        if let pending = pendingFollowUps(for: contact).first {
            let isOverdue = pending.followUpDate.map { $0 < Date() } ?? false
            return SuggestedFollowUp(
                contact: contact,
                action: pending.followUpAction ?? "Follow up",
                urgency: isOverdue ? .high : .medium,
                reason: isOverdue ? "Overdue follow-up" : "Scheduled follow-up"
            )
        }

        // Suggest based on warmth and time
        switch contact.warmth {
        case .hot:
            if days >= 14 {
                return SuggestedFollowUp(
                    contact: contact,
                    action: "Check in or share relevant content",
                    urgency: .medium,
                    reason: "Keep hot connection warm (\(days) days since contact)"
                )
            }
        case .warm:
            if days >= 30 {
                return SuggestedFollowUp(
                    contact: contact,
                    action: "Reconnect with update on your search",
                    urgency: .medium,
                    reason: "Maintain warm connection (\(days) days since contact)"
                )
            }
        case .cold:
            if days >= 60 {
                return SuggestedFollowUp(
                    contact: contact,
                    action: "Re-engage with personalized message",
                    urgency: .low,
                    reason: "Reactivate cold contact (\(days) days since contact)"
                )
            }
        case .dormant:
            // Only suggest if they're at a target company or offered help
            if contact.isAtTargetCompany || contact.hasOfferedToHelp {
                return SuggestedFollowUp(
                    contact: contact,
                    action: "Reconnect - they may still be valuable",
                    urgency: .low,
                    reason: contact.isAtTargetCompany ? "At target company" : "Previously offered help"
                )
            }
        }

        return nil
    }

    // MARK: - Analytics

    /// Get relationship health summary
    func healthSummary() -> RelationshipHealthSummary {
        let contacts = contactStore.allContacts

        let byWarmth = Dictionary(grouping: contacts) { $0.warmth }
            .mapValues { $0.count }

        let byHealth = Dictionary(grouping: contacts) { $0.relationshipHealth }
            .mapValues { $0.count }

        let avgDaysSinceContact: Double = {
            let daysValues = contacts.compactMap { $0.daysSinceContact }
            guard !daysValues.isEmpty else { return 0 }
            return Double(daysValues.reduce(0, +)) / Double(daysValues.count)
        }()

        return RelationshipHealthSummary(
            totalContacts: contacts.count,
            hotCount: byWarmth[.hot] ?? 0,
            warmCount: byWarmth[.warm] ?? 0,
            coldCount: byWarmth[.cold] ?? 0,
            dormantCount: byWarmth[.dormant] ?? 0,
            healthyCount: byHealth[.healthy] ?? 0,
            needsAttentionCount: byHealth[.needsAttention] ?? 0,
            decayingCount: byHealth[.decaying] ?? 0,
            averageDaysSinceContact: avgDaysSinceContact,
            overdueFollowUpsCount: interactionStore.overdueFollowUps.count
        )
    }

    /// Get contacts that would benefit from outreach before an event
    func contactsForEventOutreach(eventId: UUID) -> [NetworkingContact] {
        // Get contacts who might be attending similar events
        // or work at companies likely to be represented
        contactStore.allContacts.filter { contact in
            // Prioritize warm/hot contacts and those at target companies
            (contact.warmth == .hot || contact.warmth == .warm || contact.isAtTargetCompany) &&
            contact.relationshipHealth != .dormant
        }
    }
}

// MARK: - Supporting Types

enum WarmthUpgradeReason {
    case hadMeeting
    case hadConversation
    case respondedPositively
    case receivedReferral
    case offeredHelp
    case sentMessage
}

struct SuggestedFollowUp {
    let contact: NetworkingContact
    let action: String
    let urgency: FollowUpUrgency
    let reason: String
}

enum FollowUpUrgency: String, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var color: String {
        switch self {
        case .high: return "red"
        case .medium: return "orange"
        case .low: return "blue"
        }
    }
}

struct RelationshipHealthSummary {
    let totalContacts: Int
    let hotCount: Int
    let warmCount: Int
    let coldCount: Int
    let dormantCount: Int
    let healthyCount: Int
    let needsAttentionCount: Int
    let decayingCount: Int
    let averageDaysSinceContact: Double
    let overdueFollowUpsCount: Int

    var activeContactsCount: Int {
        hotCount + warmCount + coldCount
    }

    var healthyPercentage: Double {
        guard totalContacts > 0 else { return 0 }
        return Double(healthyCount) / Double(totalContacts)
    }
}
