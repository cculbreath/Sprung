//
//  TimelineManagementService.swift
//  Sprung
//
//  Service for managing timeline operations and user timeline updates.
//  Extracted from OnboardingInterviewCoordinator to reduce complexity.
//
import Foundation
import SwiftyJSON
/// Service that handles timeline management operations
actor TimelineManagementService: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator
    private let phaseTransitionController: PhaseTransitionController
    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        phaseTransitionController: PhaseTransitionController
    ) {
        self.eventBus = eventBus
        self.phaseTransitionController = phaseTransitionController
    }

    // MARK: - Timeline Card Operations
    func createTimelineCard(fields: JSON) async -> JSON {
        var card = fields
        // Add ID if not present
        if card["id"].string == nil {
            card["id"].string = UUID().uuidString
        }
        // Emit event to create timeline card
        await eventBus.publish(.timelineCardCreated(card: card))
        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["id"].string = card["id"].string
        return result
    }
    func updateTimelineCard(id: String, fields: JSON) async -> JSON {
        // Emit event to update timeline card
        await eventBus.publish(.timelineCardUpdated(id: id, fields: fields))
        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["id"].string = id
        return result
    }
    func deleteTimelineCard(id: String) async -> JSON {
        // Emit event to delete timeline card
        await eventBus.publish(.timelineCardDeleted(id: id))
        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["id"].string = id
        return result
    }
    func reorderTimelineCards(orderedIds: [String]) async -> JSON {
        // Emit event to reorder timeline cards
        await eventBus.publish(.timelineCardsReordered(ids: orderedIds))
        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["count"].int = orderedIds.count
        return result
    }
    // MARK: - Phase Transition Support
    func requestPhaseTransition(from: String, to: String, reason: String?) async {
        await phaseTransitionController.requestPhaseTransition(from: from, to: to, reason: reason)
    }
    func missingObjectives() async -> [String] {
        await phaseTransitionController.missingObjectives()
    }
}
