import Foundation
import SwiftyJSON

/// Helper utility for building tool argument payloads following consistent patterns.
/// Reduces boilerplate when constructing JSON arguments for tool calls.
struct ToolPayloadBuilder {
    /// Build arguments for submit_for_validation tool
    static func validationPayload(
        dataType: String,
        data: JSON,
        message: String?
    ) -> JSON {
        var args = JSON()
        args["dataType"].string = dataType
        args["data"] = data
        if let message {
            args["message"].string = message
        }
        return args
    }

    /// Build arguments for persist_data tool
    static func persistPayload(
        dataType: String,
        data: JSON
    ) -> JSON {
        var args = JSON()
        args["dataType"].string = dataType
        args["data"] = data
        return args
    }

    /// Build arguments for get_user_upload tool
    static func uploadPayload(
        uploadType: String,
        prompt: String,
        allowMultiple: Bool = false,
        acceptedFormats: [String]? = nil
    ) -> JSON {
        var args = JSON()
        args["uploadType"].string = uploadType
        args["prompt"].string = prompt
        if allowMultiple {
            args["allowMultiple"].bool = true
        }
        if let formats = acceptedFormats {
            args["acceptedFormats"] = JSON(formats)
        }
        return args
    }

    /// Build arguments for set_objective_status tool
    static func objectiveStatusPayload(
        objectiveId: String,
        status: String
    ) -> JSON {
        var args = JSON()
        args["objective_id"].string = objectiveId
        args["status"].string = status
        return args
    }

    /// Build arguments for generate_knowledge_card tool
    static func knowledgeCardPayload(
        title: String,
        achievements: [[String: Any]]
    ) -> JSON {
        var args = JSON()
        args["title"].string = title
        args["achievements"] = JSON(achievements)
        return args
    }

    /// Build arguments for extract_document tool
    static func extractionPayload(
        fileURL: String,
        purpose: String,
        returnTypes: [String] = ["artifact_record"]
    ) -> JSON {
        var args = JSON()
        args["file_url"].string = fileURL
        args["purpose"].string = purpose
        args["return_types"] = JSON(returnTypes)
        return args
    }

    /// Build arguments for get_user_option tool
    static func choicePayload(
        title: String,
        options: [[String: String]],
        isMultiSelect: Bool = false
    ) -> JSON {
        var args = JSON()
        args["title"].string = title
        args["options"] = JSON(options)
        if isMultiSelect {
            args["multiSelect"].bool = true
        }
        return args
    }
}
