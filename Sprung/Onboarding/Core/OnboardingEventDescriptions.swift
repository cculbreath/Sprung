//
//  OnboardingEventDescriptions.swift
//  Sprung
//
//  Routing enum and diagnostic log descriptions for OnboardingEvent.
//
import Foundation
@preconcurrency import SwiftyJSON

// MARK: - Event Topics

/// Event topics for routing
enum EventTopic: String, CaseIterable {
    case llm = "LLM"
    case toolpane = "Toolpane"
    case artifact = "Artifact"
    case userInput = "UserInput"
    case state = "State"
    case phase = "Phase"
    case objective = "Objective"
    case tool = "Tool"
    case timeline = "Timeline"
    case sectionCard = "SectionCard"
    case publicationCard = "PublicationCard"
    case processing = "Processing"
}

// MARK: - OnboardingEvent Helpers

extension OnboardingEvent {
    /// Extract the topic from the event
    var topic: EventTopic {
        switch self {
        case .llm: return .llm
        case .processing: return .processing
        case .toolpane: return .toolpane
        case .artifact: return .artifact
        case .state: return .state
        case .phase: return .phase
        case .objective: return .objective
        case .tool: return .tool
        case .timeline: return .timeline
        case .sectionCard: return .sectionCard
        case .publicationCard: return .publicationCard
        }
    }

    /// Concise log description that avoids logging full JSON payloads
    var logDescription: String {
        switch self {
        case .llm(let event):
            return event.logDescription
        case .processing(let event):
            return event.logDescription
        case .toolpane(let event):
            return event.logDescription
        case .artifact(let event):
            return event.logDescription
        case .state(let event):
            return event.logDescription
        case .phase(let event):
            return event.logDescription
        case .objective(let event):
            return event.logDescription
        case .tool(let event):
            return event.logDescription
        case .timeline(let event):
            return event.logDescription
        case .sectionCard(let event):
            return event.logDescription
        case .publicationCard(let event):
            return event.logDescription
        }
    }
}

// MARK: - Nested Event Log Descriptions

extension OnboardingEvent.LLMEvent {
    var logDescription: String {
        switch self {
        case .streamingMessageBegan(let id, _, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "llm.streamingMessageBegan(id: \(id))\(statusInfo)"
        case .streamingMessageUpdated(let id, _, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "llm.streamingMessageUpdated(id: \(id))\(statusInfo)"
        case .streamingMessageFinalized(let id, let finalText, let toolCalls, _):
            let textPreview = finalText.prefix(50).replacingOccurrences(of: "\n", with: " ")
            return "llm.streamingMessageFinalized(id: \(id), text: \"\(textPreview)...\", toolCalls: \(toolCalls?.count ?? 0))"
        case .chatboxUserMessageAdded(let messageId):
            return "llm.chatboxUserMessageAdded(\(messageId.prefix(8))...)"
        case .userMessageFailed(let messageId, _, let error):
            return "llm.userMessageFailed(\(messageId.prefix(8))..., error: \(error.prefix(50)))"
        case .userMessageSent(let messageId, _, let isSystemGenerated):
            return "llm.userMessageSent(\(messageId.prefix(8))..., isSystemGenerated: \(isSystemGenerated))"
        case .coordinatorMessageSent(let messageId, _):
            return "llm.coordinatorMessageSent(\(messageId.prefix(8))...)"
        case .sentToolResponseMessage(let messageId, _):
            return "llm.sentToolResponseMessage(\(messageId.prefix(8))...)"
        case .sendUserMessage(_, let isSystemGenerated, _, _):
            return "llm.sendUserMessage(isSystemGenerated: \(isSystemGenerated))"
        case .sendCoordinatorMessage:
            return "llm.sendCoordinatorMessage"
        case .toolResponseMessage:
            return "llm.toolResponseMessage"
        case .enqueueUserMessage(_, let isSystemGenerated, let chatboxId, _):
            let chatboxInfo = chatboxId.map { " chatbox:\($0.prefix(8))..." } ?? ""
            return "llm.enqueueUserMessage(system: \(isSystemGenerated)\(chatboxInfo))"
        case .enqueueToolResponse:
            return "llm.enqueueToolResponse"
        case .toolCallBatchStarted(let expectedCount, _):
            return "llm.toolCallBatchStarted(expecting \(expectedCount))"
        case .executeBatchedToolResponses(let payloads):
            return "llm.executeBatchedToolResponses(count: \(payloads.count))"
        case .executeUserMessage(_, let isSystemGenerated, let chatboxId, _, let bundled):
            let chatboxInfo = chatboxId.map { " chatbox:\($0.prefix(8))..." } ?? ""
            let bundledInfo = bundled.isEmpty ? "" : " +\(bundled.count) coord msgs"
            return "llm.executeUserMessage(system: \(isSystemGenerated)\(chatboxInfo)\(bundledInfo))"
        case .executeToolResponse:
            return "llm.executeToolResponse"
        case .executeCoordinatorMessage:
            return "llm.executeCoordinatorMessage"
        case .streamCompleted:
            return "llm.streamCompleted"
        case .cancelRequested:
            return "llm.cancelRequested"
        case .status(let status):
            return "llm.status(\(status.rawValue))"
        case .tokenUsageReceived(let modelId, let input, let output, let cached, _, let source):
            let cachedStr = cached > 0 ? ", cached: \(cached)" : ""
            return "llm.tokenUsage[\(source.displayName)]: \(modelId) - in: \(input), out: \(output)\(cachedStr)"
        case .conversationEntryAppended(let entry):
            return "llm.conversationEntryAppended(\(entry.isUser ? "user" : "assistant"), id: \(entry.id))"
        case .toolResultFilled(let callId, let status):
            return "llm.toolResultFilled(\(callId.prefix(8))..., status: \(status))"
        }
    }
}

extension OnboardingEvent.ProcessingEvent {
    var logDescription: String {
        switch self {
        case .stateChanged(let isProcessing, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "processing.stateChanged(\(isProcessing))\(statusInfo)"
        case .waitingStateChanged(let state, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "processing.waitingStateChanged(\(state ?? "nil"))\(statusInfo)"
        case .errorOccurred(let error):
            return "processing.errorOccurred(\(error.prefix(50)))"
        case .extractionStateChanged(let inProgress, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "processing.extractionStateChanged(\(inProgress))\(statusInfo)"
        case .pendingExtractionUpdated(let extraction, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "processing.pendingExtractionUpdated(\(extraction?.title ?? "nil"))\(statusInfo)"
        case .batchUploadStarted(let expectedCount):
            return "processing.batchUploadStarted(expecting \(expectedCount))"
        case .batchUploadCompleted:
            return "processing.batchUploadCompleted"
        case .gitAgentTurnStarted(let turn, let maxTurns):
            return "processing.gitAgentTurnStarted(\(turn)/\(maxTurns))"
        case .gitAgentToolExecuting(let toolName, let turn):
            return "processing.gitAgentToolExecuting(\(toolName), turn \(turn))"
        case .gitAgentProgressUpdated(let message, let turn):
            return "processing.gitAgentProgress(turn \(turn)): \(message.prefix(50))"
        case .queuedMessageCountChanged(let count):
            return "processing.queuedMessageCountChanged(\(count))"
        case .queuedMessageSent(let messageId):
            return "processing.queuedMessageSent(\(messageId.uuidString.prefix(8)))"
        }
    }
}

extension OnboardingEvent.ToolpaneEvent {
    var logDescription: String {
        switch self {
        case .choicePromptRequested:
            return "toolpane.choicePromptRequested"
        case .choicePromptCleared:
            return "toolpane.choicePromptCleared"
        case .uploadRequestPresented:
            return "toolpane.uploadRequestPresented"
        case .uploadRequestCancelled(let id):
            return "toolpane.uploadRequestCancelled(\(id))"
        case .validationPromptRequested:
            return "toolpane.validationPromptRequested"
        case .validationPromptCleared:
            return "toolpane.validationPromptCleared"
        case .applicantProfileIntakeRequested:
            return "toolpane.applicantProfileIntakeRequested"
        case .applicantProfileIntakeCleared:
            return "toolpane.applicantProfileIntakeCleared"
        case .sectionToggleRequested:
            return "toolpane.sectionToggleRequested"
        case .sectionToggleCleared:
            return "toolpane.sectionToggleCleared"
        }
    }
}

extension OnboardingEvent.ArtifactEvent {
    var logDescription: String {
        switch self {
        case .uploadCompleted(let files, let requestKind, _, _):
            return "artifact.uploadCompleted(\(files.count) files, kind: \(requestKind))"
        case .recordProduced(let record):
            return "artifact.recordProduced(\(record["id"].stringValue.prefix(8))...)"
        case .metadataUpdateRequested(let artifactId, let updates):
            return "artifact.metadataUpdateRequested(\(artifactId.prefix(8))..., \(updates.dictionaryValue.keys.count) fields)"
        case .metadataUpdated(let artifact):
            return "artifact.metadataUpdated(\(artifact["id"].stringValue.prefix(8))...)"
        case .knowledgeCardPersisted(let card):
            return "artifact.knowledgeCardPersisted(\(card["title"].stringValue.prefix(30)))"
        case .doneWithUploadsClicked:
            return "artifact.doneWithUploadsClicked"
        case .generateCardsButtonClicked:
            return "artifact.generateCardsButtonClicked"
        case .mergeComplete(let cardCount, let gapCount):
            return "artifact.mergeComplete(\(cardCount) cards, \(gapCount) gaps)"
        case .writingSamplePersisted(let sample):
            return "artifact.writingSamplePersisted(\(sample["name"].stringValue.prefix(30)))"
        case .candidateDossierPersisted:
            return "artifact.candidateDossierPersisted"
        case .experienceDefaultsGenerated(let defaults):
            let workCount = defaults["work"].arrayValue.count
            let skillsCount = defaults["skills"].arrayValue.count
            return "artifact.experienceDefaultsGenerated(\(workCount) work, \(skillsCount) skills)"
        case .voicePrimerExtractionStarted(let sampleCount):
            return "artifact.voicePrimerExtractionStarted(\(sampleCount) samples)"
        case .voicePrimerExtractionCompleted:
            return "artifact.voicePrimerExtractionCompleted"
        case .voicePrimerExtractionFailed(let error):
            return "artifact.voicePrimerExtractionFailed(\(error.prefix(50)))"
        }
    }
}

extension OnboardingEvent.StateEvent {
    var logDescription: String {
        switch self {
        case .applicantProfileStored:
            return "state.applicantProfileStored"
        case .skeletonTimelineStored:
            return "state.skeletonTimelineStored"
        case .enabledSectionsUpdated(let sections):
            return "state.enabledSectionsUpdated(\(sections.count) sections)"
        case .dossierNotesUpdated(let notes):
            return "state.dossierNotesUpdated(\(notes.count) chars)"
        case .documentCollectionActiveChanged(let isActive):
            return "state.documentCollectionActiveChanged(\(isActive))"
        case .timelineEditorActiveChanged(let isActive):
            return "state.timelineEditorActiveChanged(\(isActive))"
        case .allowedToolsUpdated(let tools):
            return "state.allowedToolsUpdated(\(tools.count) tools)"
        }
    }
}

extension OnboardingEvent.PhaseEvent {
    var logDescription: String {
        switch self {
        case .transitionRequested(let from, let to, _):
            return "phase.transitionRequested(\(from) → \(to))"
        case .transitionApplied(let phase, _):
            return "phase.transitionApplied(\(phase))"
        case .interviewCompleted:
            return "phase.interviewCompleted"
        }
    }
}

extension OnboardingEvent.ObjectiveEvent {
    var logDescription: String {
        switch self {
        case .statusUpdateRequested(let id, let status, _, _, _):
            return "objective.statusUpdateRequested(\(id) → \(status))"
        case .statusChanged(let id, let oldStatus, let newStatus, _, let source, _, _):
            let sourceInfo = source.map { " (source: \($0))" } ?? ""
            let oldInfo = oldStatus.map { "\($0) → " } ?? ""
            return "objective.statusChanged(\(id): \(oldInfo)\(newStatus)\(sourceInfo))"
        }
    }
}

extension OnboardingEvent.ToolEvent {
    var logDescription: String {
        switch self {
        case .callRequested(let toolCall, _):
            return "tool.callRequested(\(toolCall.name))"
        case .todoListUpdated(let json):
            return "tool.todoListUpdated(\(json.count) chars)"
        }
    }
}

extension OnboardingEvent.TimelineEvent {
    var logDescription: String {
        switch self {
        case .cardCreated:
            return "timeline.cardCreated"
        case .cardUpdated(let id, _):
            return "timeline.cardUpdated(\(id.prefix(8))...)"
        case .cardDeleted(let id, let fromUI):
            return "timeline.cardDeleted(\(id.prefix(8))...\(fromUI ? " fromUI" : ""))"
        case .cardsReordered(let ids):
            return "timeline.cardsReordered(\(ids.count) cards)"
        case .uiUpdateNeeded:
            return "timeline.uiUpdateNeeded"
        case .skeletonReplaced(_, let diff, _):
            if let diff = diff {
                return "timeline.skeletonReplaced(\(diff.summary))"
            }
            return "timeline.skeletonReplaced"
        }
    }
}

extension OnboardingEvent.SectionCardEvent {
    var logDescription: String {
        switch self {
        case .cardCreated(_, let sectionType):
            return "sectionCard.cardCreated(\(sectionType))"
        case .cardUpdated(let id, _, let sectionType):
            return "sectionCard.cardUpdated(\(id.prefix(8))..., \(sectionType))"
        case .cardDeleted(let id, let sectionType, let fromUI):
            return "sectionCard.cardDeleted(\(id.prefix(8))..., \(sectionType)\(fromUI ? " fromUI" : ""))"
        case .uiUpdateNeeded:
            return "sectionCard.uiUpdateNeeded"
        }
    }
}

extension OnboardingEvent.PublicationCardEvent {
    var logDescription: String {
        switch self {
        case .cardCreated:
            return "publicationCard.cardCreated"
        case .cardUpdated(let id, _):
            return "publicationCard.cardUpdated(\(id.prefix(8))...)"
        case .cardDeleted(let id, let fromUI):
            return "publicationCard.cardDeleted(\(id.prefix(8))...\(fromUI ? " fromUI" : ""))"
        case .cardsImported(let cards, let sourceType):
            return "publicationCard.cardsImported(\(cards.count) cards, \(sourceType))"
        case .uiUpdateNeeded:
            return "publicationCard.uiUpdateNeeded"
        }
    }
}
