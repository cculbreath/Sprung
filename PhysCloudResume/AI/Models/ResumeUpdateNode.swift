//
//  ResumeUpdateNode.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/9/24.
//

import Foundation
import OpenAI
import SwiftData

struct ProposedRevisionNode: Codable, Equatable {
    var id: String = ""
    var oldValue: String = ""
    var newValue: String = ""
    var valueChanged: Bool = false
    var isTitleNode: Bool = false
    var why: String = ""
    var treePath: String = ""

    // `value` has been removed. `treePath` is retained so the model can
    // provide a hierarchical hint when an ID match is ambiguous.

    // Custom initializer for creating nodes programmatically
    init(id: String = "", oldValue: String = "", newValue: String = "", valueChanged: Bool = false, isTitleNode: Bool = false, why: String = "", treePath: String = "") {
        self.id = id
        self.oldValue = oldValue
        self.newValue = newValue
        self.valueChanged = valueChanged
        self.isTitleNode = isTitleNode
        self.why = why
        self.treePath = treePath
    }

    enum CodingKeys: String, CodingKey {
        case id
        case oldValue
        case newValue
        case valueChanged
        case isTitleNode
        case why
        case treePath
    }

    // Custom decoder so that the struct stays compatible with older
    // responses that may *not* include `treePath`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        oldValue = try container.decodeIfPresent(String.self, forKey: .oldValue) ?? ""
        newValue = try container.decodeIfPresent(String.self, forKey: .newValue) ?? ""
        valueChanged = try container.decodeIfPresent(Bool.self, forKey: .valueChanged) ?? false
        isTitleNode = try container.decodeIfPresent(Bool.self, forKey: .isTitleNode) ?? false
        why = try container.decodeIfPresent(String.self, forKey: .why) ?? ""
        treePath = try container.decodeIfPresent(String.self, forKey: .treePath) ?? ""
    }

    // Encodable synthesis is fine.
}

struct RevisionsContainer: Codable, StructuredOutput {
    var revArray: [ProposedRevisionNode]

    static let example: Self = .init(revArray: [])
}

enum PostReviewAction: String, Codable {
    case accepted = "No action required. Revision Accepted."
    case acceptedWithChanges = "No action required. Revision Accepted with reviewer changes."
    case noChange = "No action required. Original value retained as recommended."
    case restored = "No action Required. Revision rejected and original value restored."
    case revise =
        "Action Required: Please update your submission to incorporate the reviewer comments."
    case rewriteNoComment = "Action Required: Revsion rejected without comment, please try again."
    case mandatedChangeNoComment = "Action Required:  Proposal to maintain original value rejected without comment. Please propose a  revised value for this field."
    case mandatedChange =
        "Action Required: Proposal to maintain original value rejected. Please propose a  revised value for this field and incorporate reviewer comments"
    case unevaluated = "Unevaluated"
}

@Observable class FeedbackNode {
    var id: String
    var originalValue: String
    var proposedRevision: String = ""
    var actionRequested: PostReviewAction = .unevaluated
    var reviewerComments: String = ""
    var isTitleNode: Bool = false
    init(
        id: String = "",
        originalValue: String = "",
        proposedRevision: String = "",
        actionRequested: PostReviewAction = .unevaluated,
        reviewerComments: String = "",
        isTitleNode: Bool = false
    ) {
        self.id = id
        self.originalValue = originalValue
        self.proposedRevision = proposedRevision
        self.actionRequested = actionRequested
        self.reviewerComments = reviewerComments
        self.isTitleNode = isTitleNode
    }
}

extension FeedbackNode: Encodable {
    enum CodingKeys: String, CodingKey {
        case id
        case originalValue
        case proposedRevision
        case actionRequested
        case reviewerComments
        case isTitleNode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(originalValue, forKey: .originalValue)
        try container.encode(proposedRevision, forKey: .proposedRevision)
        try container.encode(actionRequested, forKey: .actionRequested)
        try container.encode(reviewerComments, forKey: .reviewerComments)
        try container.encode(isTitleNode, forKey: .isTitleNode)
    }
}

func fbToJson(_ feedbackNodes: [FeedbackNode]) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted // Optional: makes the JSON output more readable
    do {
        let jsonData = try encoder.encode(feedbackNodes)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        } else {
            return nil
        }
    } catch {
        return nil
    }
}
