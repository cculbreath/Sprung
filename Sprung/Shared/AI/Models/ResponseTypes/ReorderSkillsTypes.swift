//
//  ReorderSkillsTypes.swift
//  Sprung
//
//  Created by Team on 5/14/25.
//

import Foundation

/// Represents a skill node with reordering information from the LLM
struct ReorderedSkillNode: Codable, Equatable {
    var id: String
    /// Echoed back by the LLM for context in change logs.
    var originalValue: String
    /// New position in the ordered list (0-based index).
    var newPosition: Int
    /// Brief explanation returned by the LLM.
    var reasonForReordering: String
    /// Indicates when the node represents a section title rather than an item.
    var isTitleNode: Bool = false

    // Alternative coding keys for different LLM response formats
    enum CodingKeys: String, CodingKey {
        case id
        case originalValue
        case newPosition
        case reasonForReordering
        case isTitleNode
    }
    
    // Custom initializer to handle different field names
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        originalValue = try container.decode(String.self, forKey: .originalValue)
        
        // Handle different position field names
        if let position = try? container.decode(Int.self, forKey: .newPosition) {
            newPosition = position
        } else if let position = try? decoder.container(keyedBy: AdditionalKeys.self).decode(Int.self, forKey: .recommendedPosition) {
            newPosition = position
        } else {
            throw DecodingError.keyNotFound(CodingKeys.newPosition, DecodingError.Context(
                codingPath: [CodingKeys.newPosition],
                debugDescription: "Neither newPosition nor recommendedPosition key found"
            ))
        }
        
        // Handle different reason field names
        if let reason = try? container.decode(String.self, forKey: .reasonForReordering) {
            reasonForReordering = reason
        } else if let reason = try? decoder.container(keyedBy: AdditionalKeys.self).decode(String.self, forKey: .reason) {
            reasonForReordering = reason
        } else {
            throw DecodingError.keyNotFound(CodingKeys.reasonForReordering, DecodingError.Context(
                codingPath: [CodingKeys.reasonForReordering],
                debugDescription: "Neither reasonForReordering nor reason key found"
            ))
        }
        
        // Optional fields with default values
        isTitleNode = (try? container.decodeIfPresent(Bool.self, forKey: .isTitleNode)) ?? false
    }
    
    // Additional coding keys for alternative field names
    enum AdditionalKeys: String, CodingKey {
        case recommendedPosition
        case reason
        case isTitleNode
    }
    
    // Standard initializer for creating instances directly
    init(id: String, originalValue: String, newPosition: Int, reasonForReordering: String, isTitleNode: Bool = false) {
        self.id = id
        self.originalValue = originalValue
        self.newPosition = newPosition
        self.reasonForReordering = reasonForReordering
        self.isTitleNode = isTitleNode
    }
}

/// Canonical response used throughout the app for skill reordering.
struct ReorderSkillsResponse: Codable, Equatable {
    var reorderedSkillsAndExpertise: [ReorderedSkillNode]

    enum CodingKeys: String, CodingKey {
        case reorderedSkillsAndExpertise = "reordered_skills_and_expertise"
    }
    
    // Custom initializer to handle different response formats
    init(from decoder: Decoder) throws {
        // First, try to decode as a regular container with reordered_skills_and_expertise field
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            reorderedSkillsAndExpertise = try container.decode([ReorderedSkillNode].self, forKey: .reorderedSkillsAndExpertise)
        } catch {
            // If that fails, try to decode as a direct array of nodes
            do {
                let nodes = try [ReorderedSkillNode].init(from: decoder)
                reorderedSkillsAndExpertise = nodes
            } catch let arrayDecodingError {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Could not decode as container or array: \(error.localizedDescription), \(arrayDecodingError.localizedDescription)"
                ))
            }
        }
    }
    
    // Initializer for manual creation
    init(reorderedSkillsAndExpertise: [ReorderedSkillNode]) {
        self.reorderedSkillsAndExpertise = reorderedSkillsAndExpertise
    }

    func validate() -> Bool {
        guard reorderedSkillsAndExpertise.isEmpty == false else { return false }
        return reorderedSkillsAndExpertise.allSatisfy { UUID(uuidString: $0.id) != nil }
    }
}
