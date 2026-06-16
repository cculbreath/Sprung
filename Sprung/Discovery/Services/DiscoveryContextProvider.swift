//
//  DiscoveryContextProvider.swift
//  Sprung
//
//  Provides context to LLM tools from Discovery stores and state.
//  Bridges the @MainActor coordinator with the actor-based tool executor.
//

import Foundation

// MARK: - Implementation

/// Provides context from DiscoveryCoordinator to LLM tools.
/// Bridges the @MainActor coordinator with the actor-based tool executor.
final class DiscoveryContextProviderImpl: @unchecked Sendable {
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

    private struct CompanyContact: Codable {
        var id: String
        var name: String
        var company: String
        var title: String
        var warmth: String
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

    // MARK: - Event Context

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

    // MARK: - Weekly Goals & Performance

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
