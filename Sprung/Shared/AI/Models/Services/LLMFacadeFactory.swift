//
//  LLMFacadeFactory.swift
//  Sprung
//
//  Factory for constructing LLMFacade with all internal dependencies.
//  This centralizes LLM infrastructure creation and keeps internal types hidden.
//
//  IMPORTANT: This factory is the canonical way to create LLMFacade instances.
//  Do not directly instantiate internal types prefixed with underscore (_).
//

import Foundation
import SwiftData
import SwiftOpenAI

@MainActor
struct LLMFacadeFactory {

    /// Creates a fully configured LLMFacade with OpenRouter backend.
    ///
    /// - Parameters:
    ///   - openRouterService: Service for OpenRouter model metadata
    ///   - enabledLLMStore: Store for enabled model preferences
    ///   - modelValidationService: Service for validating model capabilities
    /// - Returns: Tuple containing the configured LLMFacade and LLMService (for initialization)
    static func create(
        openRouterService: OpenRouterService,
        enabledLLMStore: EnabledLLMStore?,
        modelValidationService: ModelValidationService
    ) -> (facade: LLMFacade, llmService: OpenRouterServiceBackend) {
        let requestExecutor = LLMRequestExecutor()
        let llmService = OpenRouterServiceBackend(requestExecutor: requestExecutor)
        let client = SwiftOpenAIClientWrapper(executor: requestExecutor)

        let facade = LLMFacade(
            client: client,
            llmService: llmService,
            openRouterService: openRouterService,
            enabledLLMStore: enabledLLMStore,
            modelValidationService: modelValidationService
        )

        return (facade: facade, llmService: llmService)
    }

    /// Initializes the LLMService with required dependencies.
    ///
    /// Call this after creating the facade to complete initialization.
    ///
    /// - Parameters:
    ///   - llmService: The LLMService to initialize
    ///   - appState: Application state for configuration
    ///   - modelContext: SwiftData context for conversation persistence
    ///   - enabledLLMStore: Store for enabled model preferences
    ///   - openRouterService: Service for OpenRouter model metadata
    static func initialize(
        llmService: OpenRouterServiceBackend,
        appState: AppState,
        modelContext: ModelContext?,
        enabledLLMStore: EnabledLLMStore?,
        openRouterService: OpenRouterService?
    ) {
        llmService.initialize(
            appState: appState,
            modelContext: modelContext,
            enabledLLMStore: enabledLLMStore,
            openRouterService: openRouterService
        )
        llmService.reconfigureClient()
    }

    /// Registers OpenAI backend with the facade.
    ///
    /// - Parameters:
    ///   - facade: The facade to register with
    ///   - apiKey: OpenAI API key
    ///   - debugEnabled: Whether to enable debug logging
    /// - Returns: The OpenAIService for additional use (e.g., onboarding)
    @discardableResult
    static func registerOpenAI(
        facade: LLMFacade,
        apiKey: String,
        debugEnabled: Bool
    ) -> OpenAIService {
        let responsesConfiguration = URLSessionConfiguration.default
        // Give slow or lossy networks more time to connect and stream response events from OpenAI.
        responsesConfiguration.timeoutIntervalForRequest = 180
        responsesConfiguration.timeoutIntervalForResource = 600
        responsesConfiguration.waitsForConnectivity = true
        let responsesSession = URLSession(configuration: responsesConfiguration)
        let responsesHTTPClient = URLSessionHTTPClientAdapter(urlSession: responsesSession)

        let openAIService = OpenAIServiceFactory.service(
            apiKey: apiKey,
            httpClient: responsesHTTPClient,
            debugEnabled: debugEnabled
        )

        let client = OpenAIResponsesClient(service: openAIService)
        facade.registerClient(client, for: .openAI)

        let conversationService = OpenAIResponsesConversationService(service: openAIService)
        facade.registerConversationService(conversationService, for: .openAI)

        // Register direct service reference for specialized APIs (web search, etc.)
        facade.registerOpenAIService(openAIService)

        Logger.info("✅ OpenAI backend registered via LLMFacadeFactory", category: .appLifecycle)

        return openAIService
    }
}
