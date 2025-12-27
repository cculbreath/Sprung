//
//  DiscoveryContextProvider.swift
//  Sprung
//
//  Provides context to LLM tools from Discovery stores and state.
//  Bridges the @MainActor coordinator with the actor-based tool executor.
//

import Foundation
import SwiftyJSON

// MARK: - Context Provider Protocol

protocol DiscoveryContextProvider: Sendable {
    // Daily Tasks
    func getDailyTaskContext() async -> JSON

    // Job Sources
    func getPreferencesContext() async -> JSON
    func getExistingSourceUrls() async -> [String]

    // Networking Events
    func getExistingEventUrls() async -> [String]
    func getEventContext(eventId: String) async -> JSON
    func getEventFeedbackSummary() async -> JSON
    func getUpcomingEventsContext() async -> JSON

    // Contacts
    func getContactsAtCompanies(_ companies: [String]) async -> JSON
    func getContactsNeedingAttention() async -> JSON
    func getHotContacts() async -> JSON
    func getPendingFollowUps() async -> JSON
    func getContactContext(contactId: String) async -> JSON
    func getContactInteractionHistory(contactId: String) async -> JSON

    // User Profile
    func getUserProfileContext() async -> JSON

    // Weekly Goals & Performance
    func getWeeklyPerformanceHistory() async -> JSON
    func getPipelineStatus() async -> JSON
    func getWeeklySummaryContext() async -> JSON
    func getGoalProgressContext() async -> JSON
}

// MARK: - Implementation

/// Provides context from DiscoveryCoordinator to LLM tools
final class DiscoveryContextProviderImpl: DiscoveryContextProvider, @unchecked Sendable {
    private weak var coordinator: DiscoveryCoordinator?

    init(coordinator: DiscoveryCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Daily Tasks Context

    func getDailyTaskContext() async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator else { return JSON() }

            var context = JSON()

            // Due sources
            let dueSources = coordinator.jobSourceStore.dueSources.prefix(10)
            var sourcesArray: [JSON] = []
            for source in dueSources {
                var sourceJson = JSON()
                sourceJson["id"].string = source.id.uuidString
                sourceJson["name"].string = source.name
                sourceJson["days_since_visit"].int = source.daysSinceVisit ?? 999
                sourceJson["category"].string = source.category.rawValue
                sourcesArray.append(sourceJson)
            }
            context["due_sources"] = JSON(sourcesArray)

            // Upcoming events
            let upcomingEvents = coordinator.eventStore.upcomingEvents.prefix(5)
            var eventsArray: [JSON] = []
            for event in upcomingEvents {
                var eventJson = JSON()
                eventJson["id"].string = event.id.uuidString
                eventJson["name"].string = event.name
                eventJson["days_until"].int = event.daysUntilEvent ?? 0
                eventJson["status"].string = event.status.rawValue
                eventsArray.append(eventJson)
            }
            context["upcoming_events"] = JSON(eventsArray)

            // Events needing debrief
            let needsDebrief = coordinator.eventStore.needsDebrief.prefix(3)
            var debriefArray: [JSON] = []
            for event in needsDebrief {
                var eventJson = JSON()
                eventJson["id"].string = event.id.uuidString
                eventJson["name"].string = event.name
                debriefArray.append(eventJson)
            }
            context["needs_debrief"] = JSON(debriefArray)

            // Contacts needing attention
            let needsAttention = coordinator.contactStore.needsAttention.prefix(5)
            var contactsArray: [JSON] = []
            for contact in needsAttention {
                var contactJson = JSON()
                contactJson["id"].string = contact.id.uuidString
                contactJson["name"].string = contact.displayName
                contactJson["company"].string = contact.company ?? ""
                contactJson["days_since_contact"].int = contact.daysSinceContact ?? 999
                contactJson["warmth"].string = contact.warmth.rawValue
                contactsArray.append(contactJson)
            }
            context["contacts_needing_attention"] = JSON(contactsArray)

            // Weekly progress
            let goal = coordinator.weeklyGoalStore.currentWeek()
            var progressJson = JSON()
            progressJson["applications_actual"].int = goal.applicationActual
            progressJson["applications_target"].int = goal.applicationTarget
            progressJson["events_actual"].int = goal.eventsAttendedActual
            progressJson["events_target"].int = goal.eventsAttendedTarget
            progressJson["contacts_actual"].int = goal.newContactsActual
            progressJson["contacts_target"].int = goal.newContactsTarget
            progressJson["follow_ups_actual"].int = goal.followUpsSentActual
            progressJson["follow_ups_target"].int = goal.followUpsSentTarget
            context["weekly_progress"] = progressJson

            return context
        }
    }

    // MARK: - Preferences Context

    func getPreferencesContext() async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator else { return JSON() }

            let prefs = coordinator.preferencesStore.current()
            var json = JSON()
            json["target_sectors"] = JSON(prefs.targetSectors)
            json["primary_location"].string = prefs.primaryLocation
            json["remote_acceptable"].bool = prefs.remoteAcceptable
            json["company_size_preference"].string = prefs.companySizePreference.rawValue
            json["weekly_application_target"].int = prefs.weeklyApplicationTarget
            json["weekly_networking_target"].int = prefs.weeklyNetworkingTarget
            return json
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

    func getEventContext(eventId: String) async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator,
                  let uuid = UUID(uuidString: eventId),
                  let event = coordinator.eventStore.event(byId: uuid) else {
                return JSON()
            }

            var json = JSON()
            json["id"].string = event.id.uuidString
            json["name"].string = event.name
            json["description"].string = event.eventDescription ?? ""
            json["date"].string = ISO8601DateFormatter().string(from: event.date)
            json["time"].string = event.time ?? ""
            json["location"].string = event.location
            json["is_virtual"].bool = event.isVirtual
            json["url"].string = event.url
            json["organizer"].string = event.organizer ?? ""
            json["event_type"].string = event.eventType.rawValue
            json["estimated_attendance"].string = event.estimatedAttendance.rawValue
            json["cost"].string = event.cost ?? "Free"
            json["status"].string = event.status.rawValue
            if let recommendation = event.llmRecommendation {
                json["recommendation"].string = recommendation.rawValue
            }
            json["rationale"].string = event.llmRationale ?? ""
            return json
        }
    }

    func getEventFeedbackSummary() async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator else { return JSON() }

            let feedback = coordinator.feedbackStore.allFeedback
            var json = JSON()

            // Aggregate by event type
            var byType: [String: [EventFeedback]] = [:]
            for fb in feedback {
                let type = fb.eventType.rawValue
                byType[type, default: []].append(fb)
            }

            var typeStats: [JSON] = []
            for (type, feedbacks) in byType {
                var stat = JSON()
                stat["event_type"].string = type
                stat["count"].int = feedbacks.count
                let avgRating = feedbacks.map { $0.rating.rawValue }.reduce(0, +) / max(feedbacks.count, 1)
                stat["avg_rating"].int = avgRating
                let avgContacts = feedbacks.map { $0.contactsMade }.reduce(0, +) / max(feedbacks.count, 1)
                stat["avg_contacts"].int = avgContacts
                let recommendRate = Double(feedbacks.filter { $0.wouldRecommend }.count) / Double(max(feedbacks.count, 1))
                stat["recommend_rate"].double = recommendRate
                typeStats.append(stat)
            }
            json["by_event_type"] = JSON(typeStats)

            return json
        }
    }

    func getUpcomingEventsContext() async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator else { return JSON([]) }

            let events = coordinator.eventStore.upcomingEvents.prefix(10)
            var eventsArray: [JSON] = []
            for event in events {
                var eventJson = JSON()
                eventJson["id"].string = event.id.uuidString
                eventJson["name"].string = event.name
                eventJson["date"].string = ISO8601DateFormatter().string(from: event.date)
                eventJson["location"].string = event.location
                eventJson["days_until"].int = event.daysUntilEvent ?? 0
                eventJson["status"].string = event.status.rawValue
                eventsArray.append(eventJson)
            }
            return JSON(eventsArray)
        }
    }

    // MARK: - Contacts Context

    func getContactsAtCompanies(_ companies: [String]) async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator else { return JSON([]) }

            let lowercaseCompanies = Set(companies.map { $0.lowercased() })
            let matchingContacts = coordinator.contactStore.allContacts.filter { contact in
                guard let company = contact.company?.lowercased() else { return false }
                return lowercaseCompanies.contains(company)
            }

            var contactsArray: [JSON] = []
            for contact in matchingContacts {
                var json = JSON()
                json["id"].string = contact.id.uuidString
                json["name"].string = contact.displayName
                json["company"].string = contact.company ?? ""
                json["title"].string = contact.title ?? ""
                json["warmth"].string = contact.warmth.rawValue
                contactsArray.append(json)
            }
            return JSON(contactsArray)
        }
    }

    func getContactsNeedingAttention() async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator else { return JSON([]) }

            let contacts = coordinator.contactStore.needsAttention.prefix(10)
            var contactsArray: [JSON] = []
            for contact in contacts {
                var json = JSON()
                json["id"].string = contact.id.uuidString
                json["name"].string = contact.displayName
                json["company"].string = contact.company ?? ""
                json["days_since_contact"].int = contact.daysSinceContact ?? 999
                json["warmth"].string = contact.warmth.rawValue
                json["health"].string = contact.relationshipHealth.rawValue
                contactsArray.append(json)
            }
            return JSON(contactsArray)
        }
    }

    func getHotContacts() async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator else { return JSON([]) }

            let contacts = coordinator.contactStore.hotContacts.prefix(10)
            var contactsArray: [JSON] = []
            for contact in contacts {
                var json = JSON()
                json["id"].string = contact.id.uuidString
                json["name"].string = contact.displayName
                json["company"].string = contact.company ?? ""
                json["title"].string = contact.title ?? ""
                json["last_contact_at"].string = contact.lastContactAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
                contactsArray.append(json)
            }
            return JSON(contactsArray)
        }
    }

    func getPendingFollowUps() async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator else { return JSON([]) }

            let interactions = coordinator.interactionStore.pendingFollowUps.prefix(10)
            var followUpsArray: [JSON] = []
            for interaction in interactions {
                var json = JSON()
                json["id"].string = interaction.id.uuidString
                json["contact_id"].string = interaction.contactId.uuidString
                if let contact = coordinator.contactStore.contact(byId: interaction.contactId) {
                    json["contact_name"].string = contact.displayName
                }
                json["action"].string = interaction.followUpAction ?? ""
                json["due_date"].string = interaction.followUpDate.map { ISO8601DateFormatter().string(from: $0) } ?? ""
                followUpsArray.append(json)
            }
            return JSON(followUpsArray)
        }
    }

    func getContactContext(contactId: String) async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator,
                  let uuid = UUID(uuidString: contactId),
                  let contact = coordinator.contactStore.contact(byId: uuid) else {
                return JSON()
            }

            var json = JSON()
            json["id"].string = contact.id.uuidString
            json["name"].string = contact.displayName
            json["first_name"].string = contact.firstName ?? ""
            json["last_name"].string = contact.lastName ?? ""
            json["company"].string = contact.company ?? ""
            json["title"].string = contact.title ?? ""
            json["email"].string = contact.email ?? ""
            json["linkedin"].string = contact.linkedInUrl ?? ""
            json["relationship"].string = contact.relationship.rawValue
            json["how_we_met"].string = contact.howWeMet ?? ""
            json["warmth"].string = contact.warmth.rawValue
            json["notes"].string = contact.notes
            json["total_interactions"].int = contact.totalInteractions
            json["has_offered_to_help"].bool = contact.hasOfferedToHelp
            json["help_offered"].string = contact.helpOffered ?? ""
            return json
        }
    }

    func getContactInteractionHistory(contactId: String) async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator,
                  let uuid = UUID(uuidString: contactId) else {
                return JSON([])
            }

            let interactions = coordinator.interactionStore.interactions(forContactId: uuid).prefix(10)
            var historyArray: [JSON] = []
            for interaction in interactions {
                var json = JSON()
                json["date"].string = ISO8601DateFormatter().string(from: interaction.date)
                json["type"].string = interaction.interactionType.rawValue
                json["notes"].string = interaction.notes
                if let outcome = interaction.outcome {
                    json["outcome"].string = outcome.rawValue
                }
                historyArray.append(json)
            }
            return JSON(historyArray)
        }
    }

    // MARK: - User Profile Context

    func getUserProfileContext() async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator else { return JSON() }

            let prefs = coordinator.preferencesStore.current()
            var json = JSON()
            json["target_sectors"] = JSON(prefs.targetSectors)
            json["location"].string = prefs.primaryLocation
            // Could add more profile info from ApplicantProfile if available
            return json
        }
    }

    // MARK: - Weekly Goals & Performance

    func getWeeklyPerformanceHistory() async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator else { return JSON([]) }

            // Get last 4 weeks of goals
            let goals = coordinator.weeklyGoalStore.recentGoals(count: 4)
            var weeksArray: [JSON] = []
            for goal in goals {
                var json = JSON()
                json["week_start"].string = ISO8601DateFormatter().string(from: goal.weekStartDate)
                json["applications"].int = goal.applicationActual
                json["application_target"].int = goal.applicationTarget
                json["events"].int = goal.eventsAttendedActual
                json["contacts"].int = goal.newContactsActual
                json["follow_ups"].int = goal.followUpsSentActual
                json["time_minutes"].int = goal.actualMinutes
                weeksArray.append(json)
            }
            return JSON(weeksArray)
        }
    }

    func getPipelineStatus() async -> JSON {
        await MainActor.run {
            // This would integrate with JobApp pipeline
            // For now, return basic structure
            var json = JSON()
            json["active_applications"].int = 0
            json["pending_responses"].int = 0
            json["interviews_scheduled"].int = 0
            return json
        }
    }

    func getWeeklySummaryContext() async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator else { return JSON() }

            let summary = coordinator.thisWeeksSummary()
            var json = JSON()
            json["applications_submitted"].int = summary.goal.applicationActual
            json["application_target"].int = summary.goal.applicationTarget
            json["events_attended"].int = summary.goal.eventsAttendedActual
            json["new_contacts"].int = summary.goal.newContactsActual
            json["follow_ups_sent"].int = summary.goal.followUpsSentActual
            json["time_invested_minutes"].int = summary.goal.actualMinutes

            var topSourcesArray: [String] = []
            for source in summary.topSources {
                topSourcesArray.append(source.name)
            }
            json["top_sources"] = JSON(topSourcesArray)

            var eventsArray: [String] = []
            for event in summary.eventsAttended {
                eventsArray.append(event.name)
            }
            json["events_attended_names"] = JSON(eventsArray)

            json["new_contacts_count"].int = summary.newContacts.count

            return json
        }
    }

    func getGoalProgressContext() async -> JSON {
        await MainActor.run {
            guard let coordinator = coordinator else { return JSON() }

            let goal = coordinator.weeklyGoalStore.currentWeek()
            var json = JSON()
            json["application_progress"].double = goal.applicationProgress
            json["networking_progress"].double = goal.networkingProgress
            json["time_progress"].double = goal.timeProgress
            json["days_remaining_in_week"].int = {
                let calendar = Calendar.current
                let weekday = calendar.component(.weekday, from: Date())
                return max(0, 7 - weekday)
            }()
            return json
        }
    }
}
