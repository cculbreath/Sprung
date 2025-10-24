//
//  PersistDataTool.swift
//  Sprung
//
//  Saves intermediate interview data to disk for later retrieval.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

struct PersistDataTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "dataType": JSONSchema(
                type: .string,
                description: "Logical type of the data being persisted."
            ),
            "data": JSONSchema(
                type: .object,
                description: "Arbitrary JSON payload to store.",
                additionalProperties: true
            )
        ]

        return JSONSchema(
            type: .object,
            description: "Parameters for the persist_data tool.",
            properties: properties,
            required: ["dataType", "data"],
            additionalProperties: false
        )
    }()

    private let dataStore: InterviewDataStore

    var name: String { "persist_data" }
    var description: String { "Persist structured interview data for later phases of the onboarding process." }
    var parameters: JSONSchema { Self.schema }

    init(dataStore: InterviewDataStore) {
        self.dataStore = dataStore
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let dataType = params["dataType"].string, !dataType.isEmpty else {
            throw ToolError.invalidParameters("dataType must be a non-empty string")
        }

        let payload = params["data"]
        guard payload != .null else {
            throw ToolError.invalidParameters("data must be a JSON object to persist")
        }

        do {
            let identifier = try await dataStore.persist(dataType: dataType, payload: payload)
            var response = JSON()
            response["persisted"]["id"].string = identifier
            response["persisted"]["type"].string = dataType
            response["persisted"]["status"].string = "created"
            return .immediate(response)
        } catch {
            return .error(.executionFailed("Failed to persist data: \(error.localizedDescription)"))
        }
    }
}

