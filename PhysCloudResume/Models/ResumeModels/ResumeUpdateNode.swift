//
//  ResumeUpdateNode.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/2/24.
//
import Foundation

struct ProposedRevisionNode: Codable, Equatable {
    var id: String = ""
    var oldValue: String = ""
    var newValue: String = ""
    var valueChanged: Bool = false
    var why: String = ""
}

struct RevisionsContainer: Codable {
    var revArray: [ProposedRevisionNode]
}

enum PostReviewAction: String, Codable {
    case accepted = "No action required. Revision Accepted."
    case acceptedWithChanges = "No action required. Revision Accepted with reviewer changes."
    case noChange = "No action required. Original value retained as recommended."
    case restored = "No action Required. Revision rejected and original value restored."
    case revise =
        "Action Required: Please update your submission to incorporate the reviewer comments."
    case rewriteNoComment = "Action Required: Revsion rejected without comment, please try again."
    case mandatedChangeNoComment =
        "Action Required: Unchanged submission rejected. Please propose a revised value for this field"
    case mandatedChange =
        "Action Required: Unchanged submission rejected. Please propose a revised value for this field to incorporate reviewer comments"
    case unevaluated = "Unevaluated"
}

@Observable class FeedbackNode {
    var id: String
    var originalValue: String
    var proposedRevision: String = ""
    var actionRequested: PostReviewAction = .unevaluated
    var reviewerComments: String = ""
    init(
        id: String = "",
        originalValue: String = "",
        proposedRevision: String = "",
        actionRequested: PostReviewAction = .unevaluated,
        reviewerComments: String = ""
    ) {
        self.id = id
        self.originalValue = originalValue
        self.proposedRevision = proposedRevision
        self.actionRequested = actionRequested
        self.reviewerComments = reviewerComments
    }
}

extension FeedbackNode: Encodable {
    enum CodingKeys: String, CodingKey {
        case id
        case originalValue
        case proposedRevision
        case actionRequested
        case reviewerComments
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(originalValue, forKey: .originalValue)
        try container.encode(proposedRevision, forKey: .proposedRevision)
        try container.encode(actionRequested, forKey: .actionRequested)
        try container.encode(reviewerComments, forKey: .reviewerComments)
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
            print("Error converting JSON data to String")
            return nil
        }
    } catch {
        print("Error encoding FeedbackNodes to JSON: \(error)")
        return nil
    }
}
