//
//  SectionCardManagementService.swift
//  Sprung
//
//  Service for managing section card and publication card operations.
//  Handles non-chronological resume sections: awards, languages, references, publications.
//
import Foundation
import SwiftyJSON

/// Service that handles section card and publication card management operations
actor SectionCardManagementService: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator

    // MARK: - Initialization
    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
    }

    // MARK: - Section Card Operations (Awards, Languages, References)

    func createSectionCard(sectionType: String, fields: JSON) async -> JSON {
        var card = fields
        // Add ID if not present
        if card["id"].string == nil {
            card["id"].string = UUID().uuidString
        }
        card["sectionType"].string = sectionType

        // Emit event to create section card
        await eventBus.publish(.sectionCard(.cardCreated(card: card, sectionType: sectionType)))

        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["id"].string = card["id"].string
        result["sectionType"].string = sectionType
        return result
    }

    func updateSectionCard(id: String, sectionType: String, fields: JSON) async -> JSON {
        // Emit event to update section card
        await eventBus.publish(.sectionCard(.cardUpdated(id: id, fields: fields, sectionType: sectionType)))

        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["id"].string = id
        return result
    }

    func deleteSectionCard(id: String, sectionType: String) async -> JSON {
        // Emit event to delete section card
        await eventBus.publish(.sectionCard(.cardDeleted(id: id, sectionType: sectionType)))

        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["id"].string = id
        return result
    }

    // MARK: - Publication Card Operations

    func createPublicationCard(fields: JSON, sourceType: String = "interview") async -> JSON {
        var card = fields
        // Add ID if not present
        if card["id"].string == nil {
            card["id"].string = UUID().uuidString
        }
        card["sourceType"].string = sourceType

        // Emit event to create publication card
        await eventBus.publish(.publicationCard(.cardCreated(card: card)))

        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["id"].string = card["id"].string
        return result
    }

    func updatePublicationCard(id: String, fields: JSON) async -> JSON {
        // Emit event to update publication card
        await eventBus.publish(.publicationCard(.cardUpdated(id: id, fields: fields)))

        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["id"].string = id
        return result
    }

    func deletePublicationCard(id: String) async -> JSON {
        // Emit event to delete publication card
        await eventBus.publish(.publicationCard(.cardDeleted(id: id)))

        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["id"].string = id
        return result
    }

    func importPublicationCards(cards: [JSON], sourceType: String) async -> JSON {
        // Emit event to import multiple publication cards (from BibTeX or CV)
        await eventBus.publish(.publicationCard(.cardsImported(cards: cards, sourceType: sourceType)))

        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["count"].int = cards.count
        result["sourceType"].string = sourceType
        return result
    }
}
