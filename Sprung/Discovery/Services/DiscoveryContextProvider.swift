//
//  DiscoveryContextProvider.swift
//  Sprung
//
//  Provides context to LLM tools from Discovery stores and state.
//  Bridges the @MainActor coordinator with the actor-based tool executor.
//

import Foundation

// MARK: - Context Provider Protocol

protocol DiscoveryContextProvider: Sendable {
    // Daily Tasks
    func getDailyTaskContext() async -> String

    // Job Sources
    func getPreferencesContext() async -> String
    func getExistingSourceUrls() async -> [String]

    // Networking Events
    func getExistingEventUrls() async -> [String]
    func getEventContext(eventId: String) async -> String
    func getEventFeedbackSummary() async -> String
    func getUpcomingEventsContext() async -> String

    // Contacts
    func getContactsAtCompanies(_ companies: [String]) async -> String
    func getContactsNeedingAttention() async -> String
    func getHotContacts() async -> String
    func getPendingFollowUps() async -> String
    func getContactContext(contactId: String) async -> String
    func getContactInteractionHistory(contactId: String) async -> String

    // User Profile
    func getUserProfileContext() async -> String

    // Weekly Goals & Performance
    func getWeeklyPerformanceHistory() async -> String
    func getPipelineStatus() async -> String
    func getWeeklySummaryContext() async -> String
    func getGoalProgressContext() async -> String
}

// MARK: - Implementation

/// Provides context from DiscoveryCoordinator to LLM tools
final class DiscoveryContextProviderImpl: DiscoveryContextProvider, @unchecked Sendable {
    private weak var coordinator: DiscoveryCoordinator?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private let isoFormatter = ISO8601DateFormatter()

    init(coordinator: DiscoveryCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - JSON Encoding Helper

    private func encode<T: Encodable>(_ value: T) -> String {
        (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "{}"
    }

    // MARK: - Codable Context Types

    private struct DailyTaskContext: Codable {
        var dueSources: [DueSource]
        var upcomingEvents: [UpcomingEvent]
        var needsDebrief: [DebriefEvent]
        var contactsNeedingAttention: [AttentionContact]
        var weeklyProgress: WeeklyProgress

        struct DueSource: Codable {
            var id: String
            var name: String
            var daysSinceVisit: Int
            var category: String
        }

        struct UpcomingEvent: Codable {
            var id: String
            var name: String
            var daysUntil: Int
            var status: String
        }

        struct DebriefEvent: Codable {
            var id: String
            var name: String
        }

        struct AttentionContact: Codable {
            var id: String
            var name: String
            var company: String
            var daysSinceContact: Int
            var warmth: String
        }

        struct WeeklyProgress: Codable {
            var applicationsActual: Int
            var applicationsTarget: Int
            var eventsActual: Int
            var eventsTarget: Int
            var contactsActual: Int
            var contactsTarget: Int
            var followUpsActual: Int
            var followUpsTarget: Int
        }
    }

    private struct PreferencesContext: Codable {
        var targetSectors: [String]
        var primaryLocation: String
        var remoteAcceptable: Bool
        var companySizePreference: String
        var weeklyApplicationTarget: Int
        var weeklyNetworkingTarget: Int
    }

    private struct EventContext: Codable {
        var id: String
        var name: String
        var description: String
        var date: String
        var time: String
        var location: String
        var isVirtual: Bool
        var url: String
        var organizer: String
        var eventType: String
        var estimatedAttendance: String
        var cost: String
        var status: String
        var recommendation: String?
        var rationale: String
    }

    private struct EventTypeStat: Codable {
        var eventType: String
        var count: Int
        var avgRating: Int
        var avgContacts: Int
        var recommendRate: Double
    }

    private struct FeedbackSummary: Codable {
        var byEventType: [EventTypeStat]
    }

    private struct UpcomingEventItem: Codable {
        var id: String
        var name: String
        var date: String
        var location: String
        var daysUntil: Int
        var status: String
    }

    private struct CompanyContact: Codable {
        var id: String
        var name: String
        var company: String
        var title: String
        var warmth: String
    }

    private struct AttentionContactItem: Codable {
        var id: String
        var name: String
        var company: String
        var daysSinceContact: Int
        var warmth: String
        var health: String
    }

    private struct HotContactItem: Codable {
        var id: String
        var name: String
        var company: String
        var title: String
        var lastContactAt: String
    }

    private struct PendingFollowUpItem: Codable {
        var id: String
        var contactId: String
        var contactName: String?
        var action: String
        var dueDate: String
    }

    private struct ContactDetail: Codable {
        var id: String
        var name: String
        var firstName: String
        var lastName: String
        var company: String
        var title: String
        var email: String
        var linkedin: String
        var relationship: String
        var howWeMet: String
        var warmth: String
        var notes: String
        var totalInteractions: Int
        var hasOfferedToHelp: Bool
        var helpOffered: String
    }

    private struct InteractionItem: Codable {
        var date: String
        var type: String
        var notes: String
        var outcome: String?
    }

    private struct UserProfileContext: Codable {
        var targetSectors: [String]
        var location: String
    }

    private struct WeekPerformance: Codable {
        var weekStart: String
        var applications: Int
        var applicationTarget: Int
        var events: Int
        var contacts: Int
        var followUps: Int
        var timeMinutes: Int
    }

    private struct PipelineStatus: Codable {
        var activeApplications: Int
        var pendingResponses: Int
        var interviewsScheduled: Int
    }

    private struct WeeklySummaryContext: Codable {
        var applicationsSubmitted: Int
        var applicationTarget: Int
        var eventsAttended: Int
        var newContacts: Int
        var followUpsSent: Int
        var timeInvestedMinutes: Int
        var topSources: [String]
        var eventsAttendedNames: [String]
        var newContactsCount: Int
    }

    private struct GoalProgressContext: Codable {
        var applicationProgress: Double
        var networkingProgress: Double
        var timeProgress: Double
        var daysRemainingInWeek: Int
    }

    // MARK: - Daily Tasks Context

    func getDailyTaskContext() async -> String {
        await MainActor.run {
            guard let coordinator = coordinator else { return "{}" }

            let dueSources = coordinator.jobSourceStore.dueSources.prefix(10).map { source in
                DailyTaskContext.DueSource(
                    id: source.id.uuidString,
                    name: source.name,
                    daysSinceVisit: source.daysSinceVisit ?? 999,
                    category: source.category.rawValue
                )
            }

            let upcomingEvents = coordinator.eventStore.upcomingEvents.prefix(5).map { event in
                DailyTaskContext.UpcomingEvent(
                    id: event.id.uuidString,
                    name: event.name,
                    daysUntil: event.daysUntilEvent ?? 0,
                    status: event.status.rawValue
                )
            }

            let needsDebrief = coordinator.eventStore.needsDebrief.prefix(3).map { event in
                DailyTaskContext.DebriefEvent(
                    id: event.id.uuidString,
                    name: event.name
                )
            }

            let needsAttention = coordinator.contactStore.needsAttention.prefix(5).map { contact in
                DailyTaskContext.AttentionContact(
                    id: contact.id.uuidString,
                    name: contact.displayName,
                    company: contact.company ?? "",
                    daysSinceContact: contact.daysSinceContact ?? 999,
                    warmth: contact.warmth.rawValue
                )
            }

            let goal = coordinator.weeklyGoalStore.currentWeek()
            let weeklyProgress = DailyTaskContext.WeeklyProgress(
                applicationsActual: coordinator.weeklyGoalStore.applicationsSubmittedThisWeek(),
                applicationsTarget: goal.applicationTarget,
                eventsActual: goal.eventsAttendedActual,
                eventsTarget: goal.eventsAttendedTarget,
                contactsActual: goal.newContactsActual,
                contactsTarget: goal.newContactsTarget,
                followUpsActual: goal.followUpsSentActual,
                followUpsTarget: goal.followUpsSentTarget
            )

            let context = DailyTaskContext(
                dueSources: Array(dueSources),
                upcomingEvents: Array(upcomingEvents),
                needsDebrief: Array(needsDebrief),
                contactsNeedingAttention: Array(needsAttention),
                weeklyProgress: weeklyProgress
            )
            return encode(context)
        }
    }

    // MARK: - Preferences Context

    func getPreferencesContext() async -> String {
        await MainActor.run {
            guard let coordinator = coordinator else { return "{}" }

            let prefs = coordinator.preferencesStore.current()
            let context = PreferencesContext(
                targetSectors: prefs.targetSectors,
                primaryLocation: prefs.primaryLocation,
                remoteAcceptable: prefs.remoteAcceptable,
                companySizePreference: prefs.companySizePreference.rawValue,
                weeklyApplicationTarget: prefs.weeklyApplicationTarget,
                weeklyNetworkingTarget: prefs.weeklyNetworkingTarget
            )
            return encode(context)
        }
    }

    func getExistingSourceUrls() async -> [String] {
        await MainActor.run {
            guard let coordinator = coordinator else { return [] }
            return coordinator.jobSourceStore.sources.map { $0.url }
        }
    }

    // MARK: - Event Context

    func getExistingEventUrls() async -> [String] {
        await MainActor.run {
            guard let coordinator = coordinator else { return [] }
            return coordinator.eventStore.allEvents.map { $0.url }
        }
    }

    func getEventContext(eventId: String) async -> String {
        await MainActor.run {
            guard let coordinator = coordinator,
                  let uuid = UUID(uuidString: eventId),
                  let event = coordinator.eventStore.event(byId: uuid) else {
                return "{}"
            }

            let context = EventContext(
                id: event.id.uuidString,
                name: event.name,
                description: event.eventDescription ?? "",
                date: isoFormatter.string(from: event.date),
                time: event.time ?? "",
                location: event.location,
                isVirtual: event.isVirtual,
                url: event.url,
                organizer: event.organizer ?? "",
                eventType: event.eventType.rawValue,
                estimatedAttendance: event.estimatedAttendance.rawValue,
                cost: event.cost ?? "Free",
                status: event.status.rawValue,
                recommendation: event.llmRecommendation?.rawValue,
                rationale: event.llmRationale ?? ""
            )
            return encode(context)
        }
    }

    func getEventFeedbackSummary() async -> String {
        await MainActor.run {
            guard let coordinator = coordinator else { return "{}" }

            let feedback = coordinator.feedbackStore.allFeedback

            var byType: [String: [EventFeedback]] = [:]
            for fb in feedback {
                let type = fb.eventType.rawValue
                byType[type, default: []].append(fb)
            }

            let typeStats = byType.map { (type, feedbacks) in
                let avgRating = feedbacks.map { $0.rating.rawValue }.reduce(0, +) / max(feedbacks.count, 1)
                let avgContacts = feedbacks.map { $0.contactsMade }.reduce(0, +) / max(feedbacks.count, 1)
                let recommendRate = Double(feedbacks.filter { $0.wouldRecommend }.count) / Double(max(feedbacks.count, 1))
                return EventTypeStat(
                    eventType: type,
                    count: feedbacks.count,
                    avgRating: avgRating,
                    avgContacts: avgContacts,
                    recommendRate: recommendRate
                )
            }

            let summary = FeedbackSummary(byEventType: typeStats)
            return encode(summary)
        }
    }

    func getUpcomingEventsContext() async -> String {
        await MainActor.run {
            guard let coordinator = coordinator else { return "[]" }

            let events = coordinator.eventStore.upcomingEvents.prefix(10).map { event in
                UpcomingEventItem(
                    id: event.id.uuidString,
                    name: event.name,
                    date: isoFormatter.string(from: event.date),
                    location: event.location,
                    daysUntil: event.daysUntilEvent ?? 0,
                    status: event.status.rawValue
                )
            }
            return encode(Array(events))
        }
    }

    // MARK: - Contacts Context

    func getContactsAtCompanies(_ companies: [String]) async -> String {
        await MainActor.run {
            guard let coordinator = coordinator else { return "[]" }

            let lowercaseCompanies = Set(companies.map { $0.lowercased() })
            let matchingContacts = coordinator.contactStore.allContacts.filter { contact in
                guard let company = contact.company?.lowercased() else { return false }
                return lowercaseCompanies.contains(company)
            }

            let items = matchingContacts.map { contact in
                CompanyContact(
                    id: contact.id.uuidString,
                    name: contact.displayName,
                    company: contact.company ?? "",
                    title: contact.title ?? "",
                    warmth: contact.warmth.rawValue
                )
            }
            return encode(items)
        }
    }

    func getContactsNeedingAttention() async -> String {
        await MainActor.run {
            guard let coordinator = coordinator else { return "[]" }

            let contacts = coordinator.contactStore.needsAttention.prefix(10).map { contact in
                AttentionContactItem(
                    id: contact.id.uuidString,
                    name: contact.displayName,
                    company: contact.company ?? "",
                    daysSinceContact: contact.daysSinceContact ?? 999,
                    warmth: contact.warmth.rawValue,
                    health: contact.relationshipHealth.rawValue
                )
            }
            return encode(Array(contacts))
        }
    }

    func getHotContacts() async -> String {
        await MainActor.run {
            guard let coordinator = coordinator else { return "[]" }

            let contacts = coordinator.contactStore.hotContacts.prefix(10).map { contact in
                HotContactItem(
                    id: contact.id.uuidString,
                    name: contact.displayName,
                    company: contact.company ?? "",
                    title: contact.title ?? "",
                    lastContactAt: contact.lastContactAt.map { isoFormatter.string(from: $0) } ?? ""
                )
            }
            return encode(Array(contacts))
        }
    }

    func getPendingFollowUps() async -> String {
        await MainActor.run {
            guard let coordinator = coordinator else { return "[]" }

            let interactions = coordinator.interactionStore.pendingFollowUps.prefix(10).map { interaction in
                let contactName = coordinator.contactStore.contact(byId: interaction.contactId)?.displayName
                return PendingFollowUpItem(
                    id: interaction.id.uuidString,
                    contactId: interaction.contactId.uuidString,
                    contactName: contactName,
                    action: interaction.followUpAction ?? "",
                    dueDate: interaction.followUpDate.map { isoFormatter.string(from: $0) } ?? ""
                )
            }
            return encode(Array(interactions))
        }
    }

    func getContactContext(contactId: String) async -> String {
        await MainActor.run {
            guard let coordinator = coordinator,
                  let uuid = UUID(uuidString: contactId),
                  let contact = coordinator.contactStore.contact(byId: uuid) else {
                return "{}"
            }

            let detail = ContactDetail(
                id: contact.id.uuidString,
                name: contact.displayName,
                firstName: contact.firstName ?? "",
                lastName: contact.lastName ?? "",
                company: contact.company ?? "",
                title: contact.title ?? "",
                email: contact.email ?? "",
                linkedin: contact.linkedInUrl ?? "",
                relationship: contact.relationship.rawValue,
                howWeMet: contact.howWeMet ?? "",
                warmth: contact.warmth.rawValue,
                notes: contact.notes,
                totalInteractions: contact.totalInteractions,
                hasOfferedToHelp: contact.hasOfferedToHelp,
                helpOffered: contact.helpOffered ?? ""
            )
            return encode(detail)
        }
    }

    func getContactInteractionHistory(contactId: String) async -> String {
        await MainActor.run {
            guard let coordinator = coordinator,
                  let uuid = UUID(uuidString: contactId) else {
                return "[]"
            }

            let interactions = coordinator.interactionStore.interactions(forContactId: uuid).prefix(10).map { interaction in
                InteractionItem(
                    date: isoFormatter.string(from: interaction.date),
                    type: interaction.interactionType.rawValue,
                    notes: interaction.notes,
                    outcome: interaction.outcome?.rawValue
                )
            }
            return encode(Array(interactions))
        }
    }

    // MARK: - User Profile Context

    func getUserProfileContext() async -> String {
        await MainActor.run {
            guard let coordinator = coordinator else { return "{}" }

            let prefs = coordinator.preferencesStore.current()
            let context = UserProfileContext(
                targetSectors: prefs.targetSectors,
                location: prefs.primaryLocation
            )
            return encode(context)
        }
    }

    // MARK: - Weekly Goals & Performance

    func getWeeklyPerformanceHistory() async -> String {
        await MainActor.run {
            guard let coordinator = coordinator else { return "[]" }

            let goals = coordinator.weeklyGoalStore.recentGoals(count: 4).map { goal in
                WeekPerformance(
                    weekStart: isoFormatter.string(from: goal.weekStartDate),
                    applications: coordinator.weeklyGoalStore.applicationsSubmittedInWeek(goal.weekStartDate),
                    applicationTarget: goal.applicationTarget,
                    events: goal.eventsAttendedActual,
                    contacts: goal.newContactsActual,
                    followUps: goal.followUpsSentActual,
                    timeMinutes: goal.actualMinutes
                )
            }
            return encode(goals)
        }
    }

    func getPipelineStatus() async -> String {
        await MainActor.run {
            let status = PipelineStatus(
                activeApplications: 0,
                pendingResponses: 0,
                interviewsScheduled: 0
            )
            return encode(status)
        }
    }

    func getWeeklySummaryContext() async -> String {
        await MainActor.run {
            guard let coordinator = coordinator else { return "{}" }

            let summary = coordinator.thisWeeksSummary()
            let context = WeeklySummaryContext(
                applicationsSubmitted: coordinator.weeklyGoalStore.applicationsSubmittedThisWeek(),
                applicationTarget: summary.goal.applicationTarget,
                eventsAttended: summary.goal.eventsAttendedActual,
                newContacts: summary.goal.newContactsActual,
                followUpsSent: summary.goal.followUpsSentActual,
                timeInvestedMinutes: summary.goal.actualMinutes,
                topSources: summary.topSources.map { $0.name },
                eventsAttendedNames: summary.eventsAttended.map { $0.name },
                newContactsCount: summary.newContacts.count
            )
            return encode(context)
        }
    }

    func getGoalProgressContext() async -> String {
        await MainActor.run {
            guard let coordinator = coordinator else { return "{}" }

            let goal = coordinator.weeklyGoalStore.currentWeek()
            let appCount = coordinator.weeklyGoalStore.applicationsSubmittedThisWeek()
            let applicationProgress = goal.applicationTarget > 0
                ? min(1.0, Double(appCount) / Double(goal.applicationTarget))
                : 0.0

            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: Date())
            let daysRemaining = max(0, 7 - weekday)

            let context = GoalProgressContext(
                applicationProgress: applicationProgress,
                networkingProgress: goal.networkingProgress,
                timeProgress: goal.timeProgress,
                daysRemainingInWeek: daysRemaining
            )
            return encode(context)
        }
    }
}
