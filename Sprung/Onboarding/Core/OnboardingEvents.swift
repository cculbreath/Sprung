//
//  OnboardingEvents.swift
//  Sprung
//
//  Event schema for the onboarding system.
//  Defines all event types grouped into nested enums by topic.
//
import Foundation
@preconcurrency import SwiftyJSON

// MARK: - Supporting Types

/// Information about a processed upload file
struct ProcessedUploadInfo {
    let storageURL: URL
    let contentType: String?
    let filename: String
}

/// LLM status for status events
enum LLMStatus: String {
    case busy
    case idle
    case error
}

// MARK: - OnboardingEvent (Grouped by Topic)

/// All events that can occur during the onboarding interview, grouped by topic.
enum OnboardingEvent {
    // MARK: - Event Groups

    /// LLM and streaming events
    case llm(LLMEvent)

    /// Processing state and extraction events
    case processing(ProcessingEvent)

    /// Tool UI prompt events (choice, upload, validation)
    case toolpane(ToolpaneEvent)

    /// Artifact and upload events
    case artifact(ArtifactEvent)

    /// Data storage and state events
    case state(StateEvent)

    /// Phase transition events
    case phase(PhaseEvent)

    /// Objective status events
    case objective(ObjectiveEvent)

    /// Tool execution events
    case tool(ToolEvent)

    /// Timeline operations events
    case timeline(TimelineEvent)

    /// Section card operations events (awards, languages, references)
    case sectionCard(SectionCardEvent)

    /// Publication card operations events
    case publicationCard(PublicationCardEvent)
}

// MARK: - LLM Events

extension OnboardingEvent {
    /// Events related to LLM communication, streaming, and conversation log
    enum LLMEvent: Sendable {
        // Streaming messages
        case streamingMessageBegan(id: UUID, text: String, statusMessage: String? = nil)
        case streamingMessageUpdated(id: UUID, delta: String, statusMessage: String? = nil)
        case streamingMessageFinalized(id: UUID, finalText: String, toolCalls: [OnboardingMessage.ToolCallInfo]? = nil, statusMessage: String? = nil)

        // Message lifecycle
        case chatboxUserMessageAdded(messageId: String)
        case userMessageFailed(messageId: String, originalText: String, error: String)
        case userMessageSent(messageId: String, payload: JSON, isSystemGenerated: Bool = false)
        case coordinatorMessageSent(messageId: String, payload: JSON)
        case sentToolResponseMessage(messageId: String, payload: JSON)

        // Message requests
        case sendUserMessage(payload: JSON, isSystemGenerated: Bool = false, chatboxMessageId: String? = nil, originalText: String? = nil)
        case sendCoordinatorMessage(payload: JSON)
        case toolResponseMessage(payload: JSON)

        // Queue operations
        case enqueueUserMessage(payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String? = nil, originalText: String? = nil)
        case enqueueToolResponse(payload: JSON)

        // Batch operations
        case toolCallBatchStarted(expectedCount: Int, callIds: [String])
        case executeBatchedToolResponses(payloads: [JSON])

        // Execution events
        case executeUserMessage(payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String? = nil, originalText: String? = nil, bundledCoordinatorMessages: [JSON] = [])
        case executeToolResponse(payload: JSON)
        case executeCoordinatorMessage(payload: JSON)
        case streamCompleted
        case cancelRequested

        // Status and usage
        case status(LLMStatus)
        case tokenUsageReceived(modelId: String, inputTokens: Int, outputTokens: Int, cachedTokens: Int, reasoningTokens: Int, source: UsageSource)

        // Conversation log
        case conversationEntryAppended(entry: ConversationEntry)
        case toolResultFilled(callId: String, status: String)
    }
}

// MARK: - Processing Events

extension OnboardingEvent {
    /// Events related to processing state, extraction, and git agent progress
    enum ProcessingEvent: Sendable {
        // Processing state
        case stateChanged(isProcessing: Bool, statusMessage: String? = nil)
        case waitingStateChanged(String?, statusMessage: String? = nil)
        case errorOccurred(String)

        // Extraction state (non-blocking)
        case extractionStateChanged(inProgress: Bool, statusMessage: String? = nil)
        case pendingExtractionUpdated(OnboardingPendingExtraction?, statusMessage: String? = nil)

        // Queue state (for reactive UI updates)
        case queuedMessageCountChanged(count: Int)
        case queuedMessageSent(messageId: UUID)

        // Batch upload state
        case batchUploadStarted(expectedCount: Int)
        case batchUploadCompleted

        // Git agent progress
        case gitAgentTurnStarted(turn: Int, maxTurns: Int)
        case gitAgentToolExecuting(toolName: String, turn: Int)
        case gitAgentProgressUpdated(message: String, turn: Int)
    }
}

// MARK: - Toolpane Events

extension OnboardingEvent {
    /// Events related to tool UI prompts (choice, upload, validation, etc.)
    enum ToolpaneEvent: Sendable {
        // Choice prompts
        case choicePromptRequested(prompt: OnboardingChoicePrompt)
        case choicePromptCleared

        // Upload requests
        case uploadRequestPresented(request: OnboardingUploadRequest)
        case uploadRequestCancelled(id: UUID)

        // Validation prompts
        case validationPromptRequested(prompt: OnboardingValidationPrompt)
        case validationPromptCleared

        // Profile intake
        case applicantProfileIntakeRequested
        case applicantProfileIntakeCleared

        // Section toggle
        case sectionToggleRequested(request: OnboardingSectionToggleRequest)
        case sectionToggleCleared
    }
}

// MARK: - Artifact Events

extension OnboardingEvent {
    /// Events related to artifacts, uploads, and knowledge extraction
    enum ArtifactEvent: Sendable {
        // Upload completion
        case uploadCompleted(files: [ProcessedUploadInfo], requestKind: String, callId: String?, metadata: JSON)

        // Artifact pipeline
        case recordProduced(record: JSON)
        case metadataUpdateRequested(artifactId: String, updates: JSON)
        case metadataUpdated(artifact: JSON)

        // Knowledge cards
        case knowledgeCardPersisted(card: JSON)

        // Card generation workflow
        case doneWithUploadsClicked
        case generateCardsButtonClicked
        case mergeComplete(cardCount: Int, gapCount: Int)

        // Phase 3 artifacts
        case writingSamplePersisted(sample: JSON)
        case candidateDossierPersisted(dossier: JSON)
        case experienceDefaultsGenerated(defaults: JSON)

        // Voice primer
        case voicePrimerExtractionStarted(sampleCount: Int)
        case voicePrimerExtractionCompleted(primer: JSON)
        case voicePrimerExtractionFailed(error: String)
    }
}

// MARK: - State Events

extension OnboardingEvent {
    /// Events related to state storage and allowed tools
    enum StateEvent: Sendable {
        // Data storage
        case applicantProfileStored(JSON)
        case skeletonTimelineStored(JSON)
        case enabledSectionsUpdated(Set<String>)
        case dossierNotesUpdated(notes: String)

        // UI state
        case documentCollectionActiveChanged(Bool)
        case timelineEditorActiveChanged(Bool)

        // Allowed tools
        case allowedToolsUpdated(tools: Set<String>)
    }
}

// MARK: - Phase Events

extension OnboardingEvent {
    /// Events related to phase transitions
    enum PhaseEvent: Sendable {
        case transitionRequested(from: String, to: String, reason: String?)
        case transitionApplied(phase: String, timestamp: Date)
        case interviewCompleted(timestamp: Date)
    }
}

// MARK: - Objective Events

extension OnboardingEvent {
    /// Events related to objective status changes
    enum ObjectiveEvent: Sendable {
        case statusUpdateRequested(id: String, status: String, source: String?, notes: String?, details: [String: String]?)
        case statusChanged(id: String, oldStatus: String?, newStatus: String, phase: String, source: String?, notes: String?, details: [String: String]?)
    }
}

// MARK: - Tool Events

extension OnboardingEvent {
    /// Events related to tool execution
    enum ToolEvent: Sendable {
        case callRequested(ToolCall, statusMessage: String? = nil)
        case todoListUpdated(todoListJSON: String)
    }
}

// MARK: - Timeline Events

extension OnboardingEvent {
    /// Events related to timeline operations
    enum TimelineEvent: Sendable {
        case cardCreated(card: JSON)
        case cardUpdated(id: String, fields: JSON)
        case cardDeleted(id: String, fromUI: Bool = false)
        case cardsReordered(ids: [String])
        case uiUpdateNeeded(timeline: JSON)
        case skeletonReplaced(timeline: JSON, diff: TimelineDiff?, meta: JSON?)
    }
}

// MARK: - Section Card Events

extension OnboardingEvent {
    /// Events related to section card operations (awards, languages, references)
    enum SectionCardEvent: Sendable {
        case cardCreated(card: JSON, sectionType: String)
        case cardUpdated(id: String, fields: JSON, sectionType: String)
        case cardDeleted(id: String, sectionType: String, fromUI: Bool = false)
        case uiUpdateNeeded
    }
}

// MARK: - Publication Card Events

extension OnboardingEvent {
    /// Events related to publication card operations
    enum PublicationCardEvent: Sendable {
        case cardCreated(card: JSON)
        case cardUpdated(id: String, fields: JSON)
        case cardDeleted(id: String, fromUI: Bool = false)
        case cardsImported(cards: [JSON], sourceType: String)
        case uiUpdateNeeded
    }
}
