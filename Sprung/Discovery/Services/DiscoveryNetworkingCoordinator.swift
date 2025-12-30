//
//  DiscoveryNetworkingCoordinator.swift
//  Sprung
//
//  Coordinator for networking and job source management concerns.
//  Handles job sources, networking events, contacts, interactions, and URL validation.
//

import Foundation
import SwiftData

@Observable
@MainActor
final class DiscoveryNetworkingCoordinator {
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

    // MARK: - LLM Agent Operations

    /// Discover new job sources using LLM agent
    func discoverJobSources(
        using agentService: DiscoveryAgentService,
        sectors: [String],
        location: String,
        statusCallback: (@MainActor @Sendable (DiscoveryStatus) async -> Void)? = nil
    ) async throws {
        let result = try await agentService.discoverJobSources(
            sectors: sectors,
            location: location,
            statusCallback: statusCallback
        )

        await statusCallback?(.webSearchComplete)

        // Filter duplicates
        let candidateSources = result.sources.filter { generated in
            !jobSourceStore.exists(url: generated.url)
        }

        guard !candidateSources.isEmpty else {
            Logger.info("📋 No new sources to validate", category: .ai)
            await statusCallback?(.complete(added: 0, filtered: 0))
            return
        }

        // Validate URLs before adding
        await statusCallback?(.validatingURLs(count: candidateSources.count))
        Logger.info("🔍 Validating \(candidateSources.count) candidate sources", category: .ai)
        let urls = candidateSources.map { $0.url }
        let validationResults = await urlValidationService.validateBatch(urls)

        // Create a set of valid URLs for fast lookup
        let validUrls = Set(validationResults.filter { $0.isValid }.map { $0.url })

        // Filter to only valid sources and convert
        let validSources = candidateSources.filter { validUrls.contains($0.url) }.map { $0.toJobSource() }
        let invalidCount = candidateSources.count - validSources.count

        if invalidCount > 0 {
            Logger.warning("⚠️ Filtered out \(invalidCount) sources with invalid URLs", category: .ai)
        }

        jobSourceStore.addMultiple(validSources)

        await statusCallback?(.complete(added: validSources.count, filtered: invalidCount))
        Logger.info("✅ Discovered \(validSources.count) new job sources", category: .ai)
    }

    /// Discover networking events using LLM agent
    func discoverNetworkingEvents(
        using agentService: DiscoveryAgentService,
        sectors: [String],
        location: String,
        daysAhead: Int = 14,
        streamCallback: (@MainActor @Sendable (DiscoveryStatus, String?) async -> Void)? = nil
    ) async throws {
        let result = try await agentService.discoverNetworkingEvents(
            sectors: sectors,
            location: location,
            daysAhead: daysAhead,
            statusCallback: { status in
                await streamCallback?(status, nil)
            },
            reasoningCallback: { text in
                await streamCallback?(.webSearching(context: "networking events"), text)
            }
        )

        // Filter duplicates and add new events
        let newEvents = eventStore.filterNew(
            result.events.map { $0.toNetworkingEventOpportunity() }
        )

        eventStore.addMultiple(newEvents)

        await streamCallback?(.complete(added: newEvents.count, filtered: result.events.count - newEvents.count), nil)

        Logger.info("✅ Discovered \(newEvents.count) new events", category: .ai)
    }

    /// Generate an elevator pitch for an event using LLM agent
    func generateEventPitch(for event: NetworkingEventOpportunity, using agentService: DiscoveryAgentService) async throws -> String? {
        let result = try await agentService.prepareForEvent(
            eventId: event.id,
            focusCompanies: [],
            goals: nil
        )

        return result.pitchScript
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
