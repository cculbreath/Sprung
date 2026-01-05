//
//  LLMFacadeCapabilityValidator.swift
//  Sprung
//
//  Validates model capabilities before LLM requests.
//  Extracted from LLMFacade for single responsibility.
//

import Foundation

/// Validates model capabilities before LLM requests
@MainActor
struct LLMFacadeCapabilityValidator {
    private let enabledLLMStore: EnabledLLMStore?
    private let openRouterService: OpenRouterService
    private let modelValidationService: ModelValidationService

    init(
        enabledLLMStore: EnabledLLMStore?,
        openRouterService: OpenRouterService,
        modelValidationService: ModelValidationService
    ) {
        self.enabledLLMStore = enabledLLMStore
        self.openRouterService = openRouterService
        self.modelValidationService = modelValidationService
    }

    // MARK: - Public API

    func validate(modelId: String, requires capabilities: [ModelCapability]) async throws {
        if let store = enabledLLMStore, !store.isModelEnabled(modelId) {
            throw LLMError.clientError("Model '\(modelId)' is disabled. Enable it in AI Settings before use.")
        }
        let metadata = openRouterService.findModel(id: modelId)
        let record = enabledModelRecord(for: modelId)
        guard metadata != nil || record != nil else {
            throw LLMError.clientError("Model '\(modelId)' not found")
        }
        var missing = missingCapabilities(metadata: metadata, record: record, requires: capabilities)
        guard !missing.isEmpty else { return }

        // Attempt to refresh capabilities using validation service
        let validationResult = await modelValidationService.validateModel(modelId)
        if let capabilitiesInfo = validationResult.actualCapabilities {
            let supportsSchema = capabilitiesInfo.supportsStructuredOutputs || capabilitiesInfo.supportsResponseFormat
            let supportsReasoning = capabilitiesInfo.supportedParameters.contains { $0.lowercased().contains("reasoning") }
            enabledLLMStore?.updateModelCapabilities(
                modelId: modelId,
                supportsJSONSchema: supportsSchema,
                supportsImages: capabilitiesInfo.supportsImages,
                supportsReasoning: supportsReasoning
            )
        }
        let refreshedRecord = enabledModelRecord(for: modelId)
        let refreshedMetadata = openRouterService.findModel(id: modelId)
        missing = missingCapabilities(metadata: refreshedMetadata, record: refreshedRecord, requires: capabilities)
        guard missing.isEmpty else {
            let missingNames = missing.map { $0.displayName }.joined(separator: ", ")
            if let errorMessage = validationResult.error {
                throw LLMError.clientError("Model '\(modelId)' validation failed: \(errorMessage)")
            } else {
                throw LLMError.clientError("Model '\(modelId)' does not support: \(missingNames)")
            }
        }
    }

    // MARK: - Private Helpers

    private func enabledModelRecord(for modelId: String) -> EnabledLLM? {
        enabledLLMStore?.enabledModels.first(where: { $0.modelId == modelId })
    }

    private func supports(_ capability: ModelCapability, metadata: OpenRouterModel?, record: EnabledLLM?) -> Bool {
        switch capability {
        case .vision:
            if let supports = record?.supportsImages { return supports }
            return metadata?.supportsImages ?? false
        case .structuredOutput:
            if let supportsSchema = record?.supportsJSONSchema { return supportsSchema }
            if let supportsStructured = record?.supportsStructuredOutput { return supportsStructured }
            return metadata?.supportsStructuredOutput ?? false
        case .reasoning:
            if let supportsReasoning = record?.supportsReasoning { return supportsReasoning }
            return metadata?.supportsReasoning ?? false
        case .textOnly:
            let isTextOnly = record?.isTextToText ?? metadata?.isTextToText ?? true
            let supportsVision = record?.supportsImages ?? metadata?.supportsImages ?? false
            return isTextOnly && !supportsVision
        }
    }

    private func missingCapabilities(
        metadata: OpenRouterModel?,
        record: EnabledLLM?,
        requires capabilities: [ModelCapability]
    ) -> [ModelCapability] {
        capabilities.filter { !supports($0, metadata: metadata, record: record) }
    }
}
