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
final class EventFeedbackStore: EntityStore {
    typealias Entity = EventFeedback

    unowned let modelContext: ModelContext

    /// `@Observable` refresh counter bumped by EntityStore mutations.
    var changeVersion: Int = 0

    init(context: ModelContext) {
        modelContext = context
    }

    var allFeedback: [EventFeedback] {
        fetchAll(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    }

}
