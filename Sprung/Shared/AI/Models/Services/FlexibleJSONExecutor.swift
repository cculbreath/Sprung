//
//  FlexibleJSONExecutor.swift
//  Sprung
//
//  Encapsulates flexible JSON execution heuristics and schema tracking.
//
//  - Important: This is an internal implementation type. Use `LLMFacade` as the
//    public entry point for LLM operations.
//
import Foundation
final class _FlexibleJSONExecutor {
    private let requestExecutor: _LLMRequestExecutor
    init(requestExecutor: _LLMRequestExecutor) {
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
        let parameters = _LLMRequestBuilder.buildFlexibleJSONRequest(
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
            let dto = _LLMVendorMapper.responseDTO(from: response)
            let result = try _JSONResponseParser.parseFlexible(from: dto, as: responseType)
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
