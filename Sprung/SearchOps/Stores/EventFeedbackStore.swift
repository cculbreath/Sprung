//
//  EventFeedbackStore.swift
//  Sprung
//
//  Store for managing event feedback for learning/recommendations.
//

import SwiftData
import Foundation

@Observable
@MainActor
final class EventFeedbackStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
    }

    var allFeedback: [EventFeedback] {
        (try? modelContext.fetch(
            FetchDescriptor<EventFeedback>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )) ?? []
    }

    func add(_ feedback: EventFeedback) {
        modelContext.insert(feedback)
        saveContext()
    }

    func delete(_ feedback: EventFeedback) {
        modelContext.delete(feedback)
        saveContext()
    }

    func feedback(byId id: UUID) -> EventFeedback? {
        allFeedback.first { $0.id == id }
    }

    func feedback(forEventId eventId: UUID) -> EventFeedback? {
        allFeedback.first { $0.eventOpportunityId == eventId }
    }

    // MARK: - Aggregated Analysis

    func feedback(forEventType type: NetworkingEventType) -> [EventFeedback] {
        allFeedback.filter { $0.eventType == type }
    }

    func feedback(forOrganizer organizer: String) -> [EventFeedback] {
        allFeedback.filter { $0.organizer?.lowercased() == organizer.lowercased() }
    }

    // MARK: - Statistics

    func averageRating(forEventType type: NetworkingEventType) -> Double? {
        let feedbacks = feedback(forEventType: type)
        guard !feedbacks.isEmpty else { return nil }
        let total = feedbacks.reduce(0) { $0 + $1.rating.rawValue }
        return Double(total) / Double(feedbacks.count)
    }

    func averageRating(forOrganizer organizer: String) -> Double? {
        let feedbacks = feedback(forOrganizer: organizer)
        guard !feedbacks.isEmpty else { return nil }
        let total = feedbacks.reduce(0) { $0 + $1.rating.rawValue }
        return Double(total) / Double(feedbacks.count)
    }

    func averageContactsMade(forEventType type: NetworkingEventType) -> Double? {
        let feedbacks = feedback(forEventType: type)
        guard !feedbacks.isEmpty else { return nil }
        let total = feedbacks.reduce(0) { $0 + $1.contactsMade }
        return Double(total) / Double(feedbacks.count)
    }

    func averageQualityContactsMade(forEventType type: NetworkingEventType) -> Double? {
        let feedbacks = feedback(forEventType: type)
        guard !feedbacks.isEmpty else { return nil }
        let total = feedbacks.reduce(0) { $0 + $1.qualityContactsMade }
        return Double(total) / Double(feedbacks.count)
    }

    func recommendRate(forEventType type: NetworkingEventType) -> Double? {
        let feedbacks = feedback(forEventType: type)
        guard !feedbacks.isEmpty else { return nil }
        let recommended = feedbacks.filter { $0.wouldRecommend }.count
        return Double(recommended) / Double(feedbacks.count)
    }

    // MARK: - Summary for LLM Context

    struct EventTypeSummary: Codable {
        let eventType: String
        let count: Int
        let averageRating: Double?
        let averageContactsMade: Double?
        let recommendRate: Double?
    }

    func aggregatedSummary() -> [EventTypeSummary] {
        var summaries: [EventTypeSummary] = []

        for type in NetworkingEventType.allCases {
            let feedbacks = feedback(forEventType: type)
            guard !feedbacks.isEmpty else { continue }

            summaries.append(EventTypeSummary(
                eventType: type.rawValue,
                count: feedbacks.count,
                averageRating: averageRating(forEventType: type),
                averageContactsMade: averageContactsMade(forEventType: type),
                recommendRate: recommendRate(forEventType: type)
            ))
        }

        return summaries.sorted { ($0.averageRating ?? 0) > ($1.averageRating ?? 0) }
    }

    struct OrganizerSummary: Codable {
        let organizer: String
        let count: Int
        let averageRating: Double?
    }

    func organizerSummaries() -> [OrganizerSummary] {
        let organizers = Set(allFeedback.compactMap { $0.organizer })

        return organizers.map { organizer in
            let feedbacks = feedback(forOrganizer: organizer)
            return OrganizerSummary(
                organizer: organizer,
                count: feedbacks.count,
                averageRating: averageRating(forOrganizer: organizer)
            )
        }.sorted { ($0.averageRating ?? 0) > ($1.averageRating ?? 0) }
    }
}
