import Foundation
@preconcurrency import SwiftyJSON

struct OnboardingToolCall: @unchecked Sendable {
    let identifier: String
    let tool: String
    let arguments: JSON
}

struct OnboardingLLMResponse {
    let assistantReply: String
    let deltaUpdates: [JSON]
    let knowledgeCards: [JSON]
    let factLedgerEntries: [JSON]
    let skillMapDelta: JSON?
    let styleProfile: JSON?
    let writingSamples: [JSON]
    let profileContext: String?
    let needsVerification: [String]
    let nextQuestions: [OnboardingQuestion]
    let toolCalls: [OnboardingToolCall]
}

enum OnboardingLLMResponseParser {
    static func parse(_ text: String) throws -> OnboardingLLMResponse {
        guard let json = extractJSON(from: text) else {
            throw OnboardingInterviewService.OnboardingError.invalidResponseFormat
        }

        let assistantReply = json["assistant_reply"].string ??
            json["assistant_message"].string ??
            text.trimmingCharacters(in: .whitespacesAndNewlines)

        var deltaUpdates: [JSON] = []
        if let array = json["delta_update"].array {
            deltaUpdates = array
        } else if json["delta_update"].type == .dictionary {
            deltaUpdates = [json["delta_update"]]
        }

        let knowledgeCards = json["knowledge_cards"].arrayValue
        let factLedgerEntries = json["fact_ledger"].arrayValue
        let skillMapDelta: JSON? = json["skill_map_delta"].type == .null ? nil : json["skill_map_delta"]
        let styleProfile: JSON? = json["style_profile"].type == .null ? nil : json["style_profile"]
        let writingSamples = json["writing_samples"].arrayValue
        let profileContext = json["profile_context"].string
        let needsVerification = json["needs_verification"].arrayValue.compactMap { $0.string }

        let questions = json["next_questions"].arrayValue.compactMap { item -> OnboardingQuestion? in
            guard let id = item["id"].string ?? item["title"].string else { return nil }
            let text = item["question"].string ?? item["text"].string ?? ""
            if text.isEmpty { return nil }
            return OnboardingQuestion(id: id, text: text)
        }

        let toolCalls = json["tool_calls"].arrayValue.compactMap { item -> OnboardingToolCall? in
            guard let name = item["tool"].string else { return nil }
            let identifier = item["id"].string ?? UUID().uuidString
            return OnboardingToolCall(identifier: identifier, tool: name, arguments: item["args"])
        }

        return OnboardingLLMResponse(
            assistantReply: assistantReply,
            deltaUpdates: deltaUpdates,
            knowledgeCards: knowledgeCards,
            factLedgerEntries: factLedgerEntries,
            skillMapDelta: skillMapDelta,
            styleProfile: styleProfile,
            writingSamples: writingSamples,
            profileContext: profileContext,
            needsVerification: needsVerification,
            nextQuestions: questions,
            toolCalls: toolCalls
        )
    }

    private static func extractJSON(from text: String) -> JSON? {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        if let data = cleaned.data(using: .utf8),
           let json = try? JSON(data: data), json.type != .null {
            return json
        }

        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            return nil
        }

        let substring = cleaned[start...end]
        if let data = String(substring).data(using: .utf8),
           let json = try? JSON(data: data), json.type != .null {
            return json
        }

        return nil
    }
}
