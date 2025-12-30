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
}
