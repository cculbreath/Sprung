//
//  SearchOpsNetworkingCoordinator.swift
//  Sprung
//
//  Coordinator for networking and job source management concerns.
//  Handles job sources, networking events, contacts, interactions, and URL validation.
//

import Foundation
import SwiftData

@Observable
@MainActor
final class SearchOpsNetworkingCoordinator {
    // MARK: - Stores

    let jobSourceStore: JobSourceStore
    let eventStore: NetworkingEventStore
    let contactStore: NetworkingContactStore
    let interactionStore: NetworkingInteractionStore
    let feedbackStore: EventFeedbackStore

    // MARK: - Services

    let urlValidationService: URLValidationService

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.jobSourceStore = JobSourceStore(context: modelContext)
        self.eventStore = NetworkingEventStore(context: modelContext)
        self.contactStore = NetworkingContactStore(context: modelContext)
        self.interactionStore = NetworkingInteractionStore(context: modelContext)
        self.feedbackStore = EventFeedbackStore(context: modelContext)
        self.urlValidationService = URLValidationService()
    }

    func initialize() {
        // Update relationship warmth levels
        contactStore.updateAllWarmthLevels()
    }

    // MARK: - Module State Checks

    var hasActiveSources: Bool {
        !jobSourceStore.activeSources.isEmpty
    }

    // MARK: - Source Operations

    func visitSource(_ source: JobSource) {
        jobSourceStore.markVisited(source)
    }

    // MARK: - Source Validation

    func validateSources() async {
        let sourcesToValidate = jobSourceStore.sourcesNeedingRevalidation

        guard !sourcesToValidate.isEmpty else {
            Logger.debug("📋 No sources need revalidation", category: .networking)
            return
        }

        Logger.info("🔍 Validating \(sourcesToValidate.count) job sources", category: .networking)

        let urls = sourcesToValidate.map { $0.url }
        let results = await urlValidationService.validateBatch(urls)

        for result in results {
            if let source = jobSourceStore.source(byUrl: result.url) {
                jobSourceStore.updateValidation(source, valid: result.isValid)

                if !result.isValid {
                    Logger.warning("⚠️ Source validation failed: \(source.name) - \(result.error ?? "Unknown")", category: .networking)
                }
            }
        }

        Logger.info("✅ Source validation complete", category: .networking)
    }

    // MARK: - Event Workflow Helpers

    func recordEventAttendance(_ event: NetworkingEventOpportunity, weeklyGoalStore: WeeklyGoalStore) {
        eventStore.markAsAttended(event)
        weeklyGoalStore.incrementEventsAttended()
    }

    func recordEventDebrief(
        _ event: NetworkingEventOpportunity,
        contacts: [NetworkingContact],
        rating: EventRating,
        wouldRecommend: Bool,
        whatWorked: String?,
        whatDidntWork: String?,
        weeklyGoalStore: WeeklyGoalStore
    ) {
        // Update event
        event.contactCount = contacts.count
        event.eventRating = rating
        event.wouldRecommend = wouldRecommend
        event.whatWorked = whatWorked
        event.whatDidntWork = whatDidntWork
        eventStore.markAsDebriefed(event)

        // Record feedback for learning
        let feedback = EventFeedback()
        feedback.eventOpportunityId = event.id
        feedback.eventType = event.eventType
        feedback.organizer = event.organizer
        feedback.attendanceSize = event.estimatedAttendance
        feedback.wasVirtual = event.isVirtual
        feedback.cost = event.cost
        feedback.rating = rating
        feedback.contactsMade = contacts.count
        feedback.qualityContactsMade = contacts.filter { $0.warmth == .hot }.count
        feedback.wouldRecommend = wouldRecommend
        feedback.whatWorked = whatWorked
        feedback.whatDidntWork = whatDidntWork
        feedbackStore.add(feedback)

        // Update weekly goal
        weeklyGoalStore.incrementNewContacts(count: contacts.count)

        Logger.info("📝 Event debrief recorded: \(event.name) - \(contacts.count) contacts", category: .ai)
    }

    // MARK: - Contact Workflow Helpers

    func recordContactInteraction(
        _ contact: NetworkingContact,
        type: InteractionType,
        notes: String = "",
        outcome: InteractionOutcome? = nil,
        followUpNeeded: Bool = false,
        followUpAction: String? = nil,
        followUpDate: Date? = nil,
        weeklyGoalStore: WeeklyGoalStore
    ) {
        let interaction = NetworkingInteraction(contactId: contact.id, type: type)
        interaction.notes = notes
        interaction.outcome = outcome
        interaction.followUpNeeded = followUpNeeded
        interaction.followUpAction = followUpAction
        interaction.followUpDate = followUpDate
        interactionStore.add(interaction)

        // Update contact
        contactStore.recordInteraction(contact, type: type.rawValue)

        // Upgrade warmth if positive outcome
        if outcome == .positive || outcome == .referralOffered || outcome == .introOffered {
            if contact.warmth != .hot {
                contactStore.updateWarmth(contact, to: .hot)
            }
        }

        // Track follow-ups
        if type.isOutbound {
            weeklyGoalStore.incrementFollowUpsSent()
        }
    }

    // MARK: - LLM Agent Operations

    /// Discover new job sources using LLM agent
    func discoverJobSources(using agentService: SearchOpsAgentService, sectors: [String], location: String) async throws {
        let result = try await agentService.discoverJobSources(
            sectors: sectors,
            location: location
        )

        // Filter duplicates and add new sources
        let newSources = result.sources.filter { generated in
            !jobSourceStore.exists(url: generated.url)
        }.map { $0.toJobSource() }

        jobSourceStore.addMultiple(newSources)

        Logger.info("✅ Discovered \(newSources.count) new job sources", category: .ai)
    }

    /// Discover networking events using LLM agent
    func discoverNetworkingEvents(using agentService: SearchOpsAgentService, sectors: [String], location: String, daysAhead: Int = 14) async throws {
        let result = try await agentService.discoverNetworkingEvents(
            sectors: sectors,
            location: location,
            daysAhead: daysAhead
        )

        // Filter duplicates and add new events
        let newEvents = eventStore.filterNew(
            result.events.map { $0.toNetworkingEventOpportunity() }
        )

        eventStore.addMultiple(newEvents)

        Logger.info("✅ Discovered \(newEvents.count) new events", category: .ai)
    }

    /// Evaluate an event for attendance using LLM agent
    func evaluateEvent(_ event: NetworkingEventOpportunity, using agentService: SearchOpsAgentService) async throws -> EventEvaluationResult {
        let result = try await agentService.evaluateEvent(eventId: event.id)

        // Update event with evaluation
        event.llmRecommendation = result.attendanceRecommendation
        event.llmRationale = result.rationale
        event.expectedValue = result.expectedValue
        event.concerns = result.concerns
        event.status = .evaluating
        eventStore.update(event)

        Logger.info("✅ Evaluated event: \(event.name) - \(result.recommendation)", category: .ai)

        return result
    }

    /// Generate an elevator pitch for an event using LLM agent
    func generateEventPitch(for event: NetworkingEventOpportunity, using agentService: SearchOpsAgentService) async throws -> String? {
        let result = try await agentService.prepareForEvent(
            eventId: event.id,
            focusCompanies: [],
            goals: nil
        )

        return result.pitchScript
    }

    /// Prepare for an event using LLM agent
    func prepareForEvent(_ event: NetworkingEventOpportunity, focusCompanies: [String] = [], goals: String? = nil, using agentService: SearchOpsAgentService) async throws -> EventPrepResult {
        let result = try await agentService.prepareForEvent(
            eventId: event.id,
            focusCompanies: focusCompanies,
            goals: goals
        )

        // Update event with prep materials
        event.goal = result.goal
        event.pitchScript = result.pitchScript

        // Encode talking points and target companies as JSON
        let encoder = JSONEncoder()
        if let talkingPointsData = try? encoder.encode(result.talkingPoints.map { $0.toTalkingPoint() }) {
            event.talkingPointsJSON = String(data: talkingPointsData, encoding: .utf8)
        }
        if let targetCompaniesData = try? encoder.encode(result.targetCompanies.map { $0.toTargetCompanyContext() }) {
            event.targetCompaniesJSON = String(data: targetCompaniesData, encoding: .utf8)
        }

        event.conversationStarters = result.conversationStarters
        event.thingsToAvoid = result.thingsToAvoid
        eventStore.update(event)

        Logger.info("✅ Prepared for event: \(event.name)", category: .ai)

        return result
    }

    /// Suggest networking actions using LLM agent
    func suggestNetworkingActions(focus: String = "balanced", using agentService: SearchOpsAgentService) async throws -> NetworkingActionsResult {
        let result = try await agentService.suggestNetworkingActions(focus: focus)

        Logger.info("✅ Suggested \(result.actions.count) networking actions", category: .ai)

        return result
    }

    /// Draft an outreach message using LLM agent
    func draftOutreachMessage(
        contact: NetworkingContact,
        purpose: String,
        channel: String,
        tone: String = "professional",
        using agentService: SearchOpsAgentService
    ) async throws -> OutreachMessageResult {
        let result = try await agentService.draftOutreachMessage(
            contactId: contact.id,
            purpose: purpose,
            channel: channel,
            tone: tone
        )

        Logger.info("✅ Drafted outreach message for: \(contact.displayName)", category: .ai)

        return result
    }

    // MARK: - Summary Data Helpers

    func eventsToday() -> [NetworkingEventOpportunity] {
        let calendar = Calendar.current
        return eventStore.upcomingEvents.filter {
            calendar.isDateInToday($0.date)
        }
    }

    func contactsNeedingAttention(limit: Int = 5) -> [NetworkingContact] {
        Array(contactStore.needsAttention.prefix(limit))
    }

    func eventsAttendedThisWeek() -> [NetworkingEventOpportunity] {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()

        return eventStore.attendedEvents.filter { event in
            guard let attendedAt = event.attendedAt else { return false }
            return attendedAt >= weekStart
        }
    }

    func newContactsThisWeek() -> [NetworkingContact] {
        contactStore.thisWeeksNewContacts
    }
}
