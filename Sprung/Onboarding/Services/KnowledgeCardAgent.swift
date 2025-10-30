import Foundation
import SwiftOpenAI
import SwiftyJSON

enum KnowledgeCardAgentError: LocalizedError {
    case emptyResponse
    case invalidEncoding
    case decodingFailed
    case missingClaims
    case emptyClaim
    case missingEvidence(claim: String)
    case citationNotFound(claim: String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Knowledge card generation returned no content."
        case .invalidEncoding:
            return "Knowledge card output was not valid UTF-8."
        case .decodingFailed:
            return "Unable to decode knowledge card JSON."
        case .missingClaims:
            return "Knowledge card must include at least one achievement."
        case .emptyClaim:
            return "Knowledge card included an empty achievement claim."
        case .missingEvidence(let claim):
            return "The claim \(claim) is missing its supporting citation."
        case .citationNotFound(let claim):
            return "Could not match the citation for claim \(claim) against provided evidence."
        }
    }
}

final class KnowledgeCardAgent {
    private let client: OpenAIService
    private let maxArtifactCharacters = 4_000
    private let maxTranscriptCharacters = 6_000

    init(client: OpenAIService) {
        self.client = client
    }

    func generateCard(for context: ExperienceContext) async throws -> KnowledgeCardDraft {
        let config = ModelProvider.forTask(.knowledgeCard)
        let textConfig = TextConfiguration(format: .jsonObject, verbosity: config.defaultVerbosity)

        let systemMessage = InputMessage(role: "system", content: .text(systemInstruction))
        let userMessage = InputMessage(role: "user", content: .text(buildPrompt(for: context)))

        var parameters = ModelResponseParameter(
            input: .array([
                .message(systemMessage),
                .message(userMessage)
            ]),
            model: .custom(config.id),
            text: textConfig
        )

        if let effort = config.defaultReasoningEffort {
            parameters.reasoning = Reasoning(effort: effort, summary: .auto)
        }

        let response = try await client.responseCreate(parameters)
        guard let output = response.outputText, !output.isEmpty else {
            throw KnowledgeCardAgentError.emptyResponse
        }
        guard let data = output.data(using: .utf8) else {
            throw KnowledgeCardAgentError.invalidEncoding
        }

        let json: JSON
        do {
            json = try JSON(data: data)
        } catch {
            throw KnowledgeCardAgentError.decodingFailed
        }

        let draft = KnowledgeCardDraft(json: json)
        return try validateCitations(in: draft, artifacts: context.artifacts)
    }

    private var systemInstruction: String {
        """
        You are Sprung's knowledge card generator. Produce a single JSON object with the keys:
        id, title, summary, source, achievements, metrics, skills.
        Requirements:
        - achievements is an array of objects with id, claim, evidence.
        - evidence includes quote, source, locator (optional), and artifact_sha (optional).
        - Every claim must reference a verbatim quote from the supplied evidence.
        - Do not fabricate citations; omit any claim that lacks supporting evidence.
        - Metrics should highlight quantified outcomes.
        - Skills should list the most relevant competencies as lowercase strings.
        - Return JSON only with no additional prose.
        """
    }

    private func buildPrompt(for context: ExperienceContext) -> String {
        let experienceJSON = context.timelineEntry.rawString(.utf8, options: [.prettyPrinted]) ?? context.timelineEntry.description

        let artifactSnippets = context.artifacts.map { artifact -> String in
            let truncated = truncate(artifact.extractedContent, limit: maxArtifactCharacters)
            let purpose = artifact.metadata["purpose"].string ?? "unspecified"
            return """
            Artifact: \(artifact.filename)
            SHA256: \(artifact.sha256 ?? "unknown")
            Purpose: \(purpose)
            Content:
            \(truncated)
            """
        }
        .joined(separator: "\n\n")

        let transcript = truncate(context.transcript, limit: maxTranscriptCharacters)

        return """
        EXPERIENCE CONTEXT (JSON):
        \(experienceJSON)

        INTERVIEW TRANSCRIPT:
        \(transcript.isEmpty ? "(No transcript provided)" : transcript)

        EVIDENCE ARTIFACTS:
        \(artifactSnippets.isEmpty ? "(No artifacts provided)" : artifactSnippets)

        Generate the knowledge card JSON now.
        """
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[text.startIndex..<index]) + "…"
    }

    private func validateCitations(in draft: KnowledgeCardDraft, artifacts: [ArtifactRecord]) throws -> KnowledgeCardDraft {
        guard !draft.achievements.isEmpty else {
            throw KnowledgeCardAgentError.missingClaims
        }

        for achievement in draft.achievements {
            guard let claim = achievement.claim.trimmedNonEmpty else {
                throw KnowledgeCardAgentError.emptyClaim
            }

            guard let quote = achievement.evidence.quote.trimmedNonEmpty else {
                throw KnowledgeCardAgentError.missingEvidence(claim: claim)
            }

            let candidateArtifacts: [ArtifactRecord]
            if let sha = achievement.evidence.artifactSHA, !sha.isEmpty {
                candidateArtifacts = artifacts.filter { $0.sha256 == sha }
            } else {
                candidateArtifacts = artifacts
            }

            let found = candidateArtifacts.contains { artifact in
                artifact.extractedContent.localizedCaseInsensitiveContains(quote)
            }

            if !found {
                throw KnowledgeCardAgentError.citationNotFound(claim: claim)
            }
        }

        return draft
    }
}
