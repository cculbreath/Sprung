import Foundation
import SwiftyJSON

@MainActor
final class OnboardingInterviewResponseProcessor {
    private let messageManager: OnboardingInterviewMessageManager
    private let artifactStore: OnboardingArtifactStore
    private let toolExecutor: OnboardingToolExecutor
    private let toolPipeline: OnboardingInterviewToolPipeline
    private let wizardManager: OnboardingInterviewWizardManager
    private let refreshArtifacts: () -> Void
    private let syncWizardStep: () -> Void
    private let persistConversationState: () async -> Void

    init(
        messageManager: OnboardingInterviewMessageManager,
        artifactStore: OnboardingArtifactStore,
        toolExecutor: OnboardingToolExecutor,
        toolPipeline: OnboardingInterviewToolPipeline,
        wizardManager: OnboardingInterviewWizardManager,
        refreshArtifacts: @escaping () -> Void,
        syncWizardStep: @escaping () -> Void,
        persistConversationState: @escaping () async -> Void
    ) {
        self.messageManager = messageManager
        self.artifactStore = artifactStore
        self.toolExecutor = toolExecutor
        self.toolPipeline = toolPipeline
        self.wizardManager = wizardManager
        self.refreshArtifacts = refreshArtifacts
        self.syncWizardStep = syncWizardStep
        self.persistConversationState = persistConversationState
    }

    func handleLLMResponse(
        _ responseText: String,
        updatingMessageId messageId: UUID? = nil
    ) async throws {
        do {
            let parsed = try OnboardingLLMResponseParser.parse(responseText)

            if !parsed.assistantReply.isEmpty {
                if let messageId = messageId {
                    messageManager.updateMessage(id: messageId, text: parsed.assistantReply)
                } else {
                    messageManager.appendAssistantMessage(parsed.assistantReply)
                }
            } else if let messageId = messageId {
                messageManager.removeMessage(withId: messageId)
            }

            if !parsed.deltaUpdates.isEmpty {
                try await toolExecutor.applyDeltaUpdates(parsed.deltaUpdates)
            }

            if !parsed.knowledgeCards.isEmpty {
                _ = artifactStore.appendKnowledgeCards(parsed.knowledgeCards)
            }

            if !parsed.factLedgerEntries.isEmpty {
                _ = artifactStore.appendFactLedgerEntries(parsed.factLedgerEntries)
            }

            if let skillMap = parsed.skillMapDelta {
                _ = artifactStore.mergeSkillMap(patch: skillMap)
            }

            if let styleProfile = parsed.styleProfile {
                artifactStore.saveStyleProfile(styleProfile)
            }

            if !parsed.writingSamples.isEmpty {
                toolExecutor.saveWritingSamples(parsed.writingSamples)
            }

            if let profileContext = parsed.profileContext?.trimmingCharacters(in: .whitespacesAndNewlines), !profileContext.isEmpty {
                artifactStore.updateProfileContext(profileContext)
            }

            if !parsed.needsVerification.isEmpty {
                _ = artifactStore.appendNeedsVerification(parsed.needsVerification)
            }

            refreshArtifacts()
            messageManager.setNextQuestions(parsed.nextQuestions)

            if !parsed.toolCalls.isEmpty {
                try await toolPipeline.process(parsed.toolCalls)
            }

            syncWizardStep()
            await persistConversationState()
        } catch {
            if let messageId = messageId {
                messageManager.removeMessage(withId: messageId)
            }

            guard let fallbackToolCalls = try? extractToolCalls(from: responseText), !fallbackToolCalls.isEmpty else {
                throw error
            }

            try await toolPipeline.process(fallbackToolCalls)
            syncWizardStep()
            await persistConversationState()
        }
    }

    private func extractToolCalls(from responseText: String) throws -> [OnboardingToolCall] {
        guard let data = responseText.data(using: .utf8) else {
            return []
        }
        let json = try JSON(data: data)
        let rawCalls = json["tool_calls"].arrayValue
        guard !rawCalls.isEmpty else {
            return []
        }

        return rawCalls.compactMap { item -> OnboardingToolCall? in
            let identifier = item["id"].string ?? UUID().uuidString
            let toolName = item["tool"].string ?? item["name"].string

            guard let tool = toolName, !tool.isEmpty else {
                return nil
            }

            var argumentsJSON = item["arguments"]
            if argumentsJSON.type == .null || (argumentsJSON.type == .string && argumentsJSON.stringValue.isEmpty) {
                argumentsJSON = item["args"]
            }

            if argumentsJSON.type == .string {
                let raw = argumentsJSON.stringValue
                if let argData = raw.data(using: .utf8), let parsed = try? JSON(data: argData) {
                    argumentsJSON = parsed
                } else {
                    argumentsJSON = JSON(parseJSON: raw)
                }
            }

            return OnboardingToolCall(identifier: identifier, tool: tool, arguments: argumentsJSON)
        }
    }
}
