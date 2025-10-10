//
//  FlexibleJSONExecutor.swift
//  PhysCloudResume
//
//  Encapsulates flexible JSON execution heuristics and schema tracking.
//

import Foundation

final class FlexibleJSONExecutor {
    private let requestExecutor: LLMRequestExecutor

    init(requestExecutor: LLMRequestExecutor) {
        self.requestExecutor = requestExecutor
    }

    func execute<T: Codable>(
        prompt: String,
        modelId: String,
        responseType: T.Type,
        temperature: Double,
        jsonSchema: JSONSchema?,
        supportsStructuredOutput: Bool,
        shouldAvoidJSONSchema: Bool,
        recordSchemaSuccess: @escaping () async -> Void,
        recordSchemaFailure: @escaping (_ reason: String) async -> Void
    ) async throws -> T {
        let parameters = LLMRequestBuilder.buildFlexibleJSONRequest(
            prompt: prompt,
            modelId: modelId,
            responseType: responseType,
            temperature: temperature,
            jsonSchema: jsonSchema,
            supportsStructuredOutput: supportsStructuredOutput,
            shouldAvoidJSONSchema: shouldAvoidJSONSchema
        )

        do {
            let response = try await requestExecutor.execute(parameters: parameters)
            let dto = LLMVendorMapper.responseDTO(from: response)
            let result = try JSONResponseParser.parseFlexible(from: dto, as: responseType)

            if supportsStructuredOutput && !shouldAvoidJSONSchema && jsonSchema != nil {
                await recordSchemaSuccess()
                Logger.info("✅ JSON schema validation successful for model: \(modelId)")
            }

            return result
        } catch {
            let description = error.localizedDescription.lowercased()
            if description.contains("response_format") || description.contains("json_schema") {
                await recordSchemaFailure(error.localizedDescription)
                Logger.debug("🚫 Recorded JSON schema failure for \(modelId): \(error.localizedDescription)")
            }
            throw error
        }
    }
}
