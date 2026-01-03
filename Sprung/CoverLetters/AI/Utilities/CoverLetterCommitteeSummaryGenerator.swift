//
//  CoverLetterCommitteeSummaryGenerator.swift
//  Sprung
//
//
import Foundation
enum CoverLetterCommitteeSummaryError: LocalizedError {
    case facadeUnavailable
    var errorDescription: String? {
        "Unable to generate the analysis summary because the AI service is unavailable."
    }
}
class CoverLetterCommitteeSummaryGenerator {
    private var llmFacade: LLMFacade?
    func configure(llmFacade: LLMFacade) {
        self.llmFacade = llmFacade
    }
    @MainActor
    func generateSummary(
        coverLetters: [CoverLetter],
        jobApp: JobApp,
        modelReasonings: [(model: String, response: BestCoverLetterResponse)],
        voteTally: [UUID: Int],
        scoreTally: [UUID: Int],
        selectedVotingScheme: VotingScheme,
        preferredModelId: String? = nil
    ) async throws -> String {
        Logger.info("🧠 Generating reasoning summary...")
        var letterAnalyses: [LetterAnalysis] = []
        for letter in coverLetters {
            let letterAnalysis: LetterAnalysis
            if selectedVotingScheme == .firstPastThePost {
                let votes = voteTally[letter.id] ?? 0
                let modelComments = modelReasonings.compactMap { reasoning -> String? in
                    if let bestUuid = reasoning.response.bestLetterUuid,
                       bestUuid == letter.id.uuidString {
                        return "\(reasoning.model): \(reasoning.response.verdict)"
                    }
                    return nil
                }
                // Track individual votes for first-past-the-post
                let modelVotes = modelReasonings.compactMap { reasoning -> ModelVote? in
                    if let bestUuid = reasoning.response.bestLetterUuid,
                       bestUuid == letter.id.uuidString {
                        return ModelVote(
                            model: reasoning.model,
                            votedForLetterId: letter.id.uuidString
                        )
                    }
                    return nil
                }
                letterAnalysis = LetterAnalysis(
                    letterId: letter.id.uuidString,
                    summaryOfModelAnalysis: modelComments.isEmpty ? "No specific comments from voting models." : modelComments.joined(separator: " | "),
                    pointsAwarded: [ModelPointsAwarded(model: "Committee Vote", points: votes)],
                    modelVotes: modelVotes
                )
            } else {
                var pointsFromModels: [ModelPointsAwarded] = []
                var modelComments: [String] = []
                var modelVotes: [ModelVote] = []
                for reasoning in modelReasonings {
                    if let scoreAllocations = reasoning.response.scoreAllocations,
                       let allocation = scoreAllocations.first(where: { $0.letterUuid == letter.id.uuidString }) {
                        pointsFromModels.append(ModelPointsAwarded(model: reasoning.model, points: allocation.score))
                        var comment = "\(reasoning.model): \(reasoning.response.verdict)"
                        if let allocationReasoning = allocation.reasoning {
                            comment += " (Score reasoning: \(allocationReasoning))"
                        }
                        modelComments.append(comment)
                        // Track individual votes for score voting (points allocation)
                        modelVotes.append(ModelVote(
                            model: reasoning.model,
                            votedForLetterId: letter.id.uuidString
                        ))
                    }
                }
                letterAnalysis = LetterAnalysis(
                    letterId: letter.id.uuidString,
                    summaryOfModelAnalysis: modelComments.isEmpty ? "No specific analysis provided." : modelComments.joined(separator: " | "),
                    pointsAwarded: pointsFromModels,
                    modelVotes: modelVotes
                )
            }
            letterAnalyses.append(letterAnalysis)
        }
        _ = CommitteeSummaryResponse(letterAnalyses: letterAnalyses)
        let summaryPrompt = buildSummaryPrompt(
            jobApp: jobApp,
            modelReasonings: modelReasonings,
            voteTally: voteTally,
            scoreTally: scoreTally,
            selectedVotingScheme: selectedVotingScheme
        )
        let jsonSchema = createJSONSchema()
        guard let llm = llmFacade else {
            throw CoverLetterCommitteeSummaryError.facadeUnavailable
        }
        let summaryModelId = preferredModelId ?? modelReasonings.first?.model ?? DefaultModels.openRouter
        let summaryResponse: CommitteeSummaryResponse = try await llm.executeFlexibleJSON(
                prompt: summaryPrompt,
                modelId: summaryModelId,
                as: CommitteeSummaryResponse.self,
                temperature: 0.7,
                jsonSchema: jsonSchema
        )
        Logger.info("🧠 Analysis summary generated using model \(summaryModelId)")
        Logger.debug("🔍 Processing \(summaryResponse.letterAnalyses.count) letter analyses")
        for analysis in summaryResponse.letterAnalyses {
            Logger.debug("🔍 Processing analysis for letterId: \(analysis.letterId)")
            if let letter = coverLetters.first(where: { $0.id.uuidString == analysis.letterId }) {
                Logger.debug("🔍 Found letter: \(letter.sequencedName)")
                let committeeFeedback = CommitteeFeedbackSummary(
                    summaryOfModelAnalysis: analysis.summaryOfModelAnalysis,
                    pointsAwarded: analysis.pointsAwarded,
                    modelVotes: analysis.modelVotes
                )
                letter.committeeFeedback = committeeFeedback
            } else {
                Logger.debug("❌ Could not find letter for ID: \(analysis.letterId)")
            }
        }
        var displaySummary = "Committee Analysis Summary:\n\n"
        Logger.debug("🔍 Building display summary from \(summaryResponse.letterAnalyses.count) analyses")
        for analysis in summaryResponse.letterAnalyses {
            if let letter = coverLetters.first(where: { $0.id.uuidString == analysis.letterId }) {
                Logger.debug("🔍 Adding analysis for \(letter.sequencedName): \(analysis.summaryOfModelAnalysis.prefix(100))...")
                displaySummary += "**\(letter.sequencedName)**\n"
                displaySummary += "\(analysis.summaryOfModelAnalysis)\n\n"
            } else {
                Logger.debug("❌ Display summary: Could not find letter for ID: \(analysis.letterId)")
                // Add available letter IDs for debugging
                let availableIds = coverLetters.map { $0.id.uuidString }
                Logger.debug("🔍 Available letter IDs: \(availableIds)")
            }
        }
        Logger.info("✅ Analysis summary generation completed")
        Logger.debug("🔍 Summary length: \(displaySummary.count) characters")
        Logger.debug("🔍 Summary preview: \(String(displaySummary.prefix(100)))...")
        return displaySummary
    }
    func createFallbackSummary(
        coverLetter: CoverLetter,
        coverLetters: [CoverLetter],
        modelReasonings: [(model: String, response: BestCoverLetterResponse)],
        voteTally: [UUID: Int],
        scoreTally: [UUID: Int],
        selectedVotingScheme: VotingScheme
    ) -> String {
        var fallbackSummary = "Committee Analysis Summary:\n\n"
        fallbackSummary += "**Voting Results:**\n"
        if selectedVotingScheme == .firstPastThePost {
            for (letterId, votes) in voteTally.sorted(by: { $0.value > $1.value }) {
                if let letter = coverLetters.first(where: { $0.id == letterId }) {
                    fallbackSummary += "• \(letter.sequencedName): \(votes) vote(s)\n"
                }
            }
        } else {
            for (letterId, score) in scoreTally.sorted(by: { $0.value > $1.value }) {
                if let letter = coverLetters.first(where: { $0.id == letterId }) {
                    fallbackSummary += "• \(letter.sequencedName): \(score) points\n"
                }
            }
        }
        fallbackSummary += "\n**Model Verdicts:**\n"
        for reasoning in modelReasonings {
            if let jobApp = coverLetter.jobApp {
                fallbackSummary += "• **\(reasoning.model)**: \(jobApp.replaceUUIDsWithLetterNames(in: reasoning.response.verdict))\n"
            } else {
                fallbackSummary += "• **\(reasoning.model)**: \(reasoning.response.verdict)\n"
            }
        }
        fallbackSummary += "\n*Note: Detailed analysis generation failed, showing basic voting summary.*"
        return fallbackSummary
    }
    // MARK: - Private Methods
    private func buildSummaryPrompt(
        jobApp: JobApp,
        modelReasonings: [(model: String, response: BestCoverLetterResponse)],
        voteTally: [UUID: Int],
        scoreTally: [UUID: Int],
        selectedVotingScheme: VotingScheme
    ) -> String {
        var summaryPrompt = "You are analyzing the reasoning from multiple AI models that evaluated cover letters for a \(jobApp.jobPosition) position at \(jobApp.companyName). "
        if selectedVotingScheme == .firstPastThePost {
            summaryPrompt += "Each model voted for their single preferred cover letter using a first-past-the-post voting system. "
        } else {
            summaryPrompt += "Each model allocated 20 points among all cover letters using a score voting system. "
        }
        summaryPrompt += "Based on the voting results and model reasoning provided, create a structured analysis for each cover letter that includes:\n"
        summaryPrompt += "1. A comprehensive summary of what the models said about this specific letter\n"
        summaryPrompt += "2. The points/votes awarded by each model\n"
        summaryPrompt += "3. Key themes in the model feedback\n\n"
        summaryPrompt += "Here are the model reasonings and vote allocations:\n\n"
        for reasoning in modelReasonings {
            if selectedVotingScheme == .firstPastThePost {
                let letterUuid = reasoning.response.bestLetterUuid ?? "Unknown"
                summaryPrompt += "**\(reasoning.model)** voted for '\(letterUuid)':\n"
            } else {
                summaryPrompt += "**\(reasoning.model)** score allocations:\n"
                if let scoreAllocations = reasoning.response.scoreAllocations {
                    for allocation in scoreAllocations {
                        summaryPrompt += "- \(allocation.letterUuid): \(allocation.score) points"
                        if let allocationReasoning = allocation.reasoning {
                            summaryPrompt += " (\(allocationReasoning))"
                        }
                        summaryPrompt += "\n"
                    }
                }
            }
            summaryPrompt += "Analysis: \(reasoning.response.strengthAndVoiceAnalysis)\n"
            summaryPrompt += "Verdict: \(reasoning.response.verdict)\n\n"
        }
        if selectedVotingScheme == .firstPastThePost {
            summaryPrompt += "Final vote tally:\n"
            for (letterId, votes) in voteTally {
                summaryPrompt += "- \(letterId.uuidString): \(votes) vote(s)\n"
            }
        } else {
            summaryPrompt += "Final score tally:\n"
            for (letterId, score) in scoreTally {
                summaryPrompt += "- \(letterId.uuidString): \(score) points\n"
            }
        }
        summaryPrompt += "\n\nProvide your analysis as a JSON response following this structure:\n"
        summaryPrompt += "```json\n"
        summaryPrompt += "{\n"
        summaryPrompt += "  \"letterAnalyses\": [\n"
        summaryPrompt += "    {\n"
        summaryPrompt += "      \"summaryOfModelAnalysis\": \"Comprehensive summary of what models said about this letter\",\n"
        summaryPrompt += "      \"pointsAwarded\": [\n"
        summaryPrompt += "        {\"model\": \"Model name\", \"points\": 0}\n"
        summaryPrompt += "      ],\n"
        summaryPrompt += "      \"modelVotes\": [\n"
        summaryPrompt += "        {\"model\": \"Model name\", \"votedForLetterId\": \"UUID\", \"reasoning\": \"Model's reasoning\"}\n"
        summaryPrompt += "      ]\n"
        summaryPrompt += "    }\n"
        summaryPrompt += "  ]\n"
        summaryPrompt += "}\n"
        summaryPrompt += "```"
        return summaryPrompt
    }
    private func createJSONSchema() -> JSONSchema {
        return JSONSchema(
            type: .object,
            properties: [
                "letterAnalyses": JSONSchema(
                    type: .array,
                    items: JSONSchema(
                        type: .object,
                        properties: [
                            "summaryOfModelAnalysis": JSONSchema(
                                type: .string,
                                description: "Comprehensive summary of model feedback for this letter"
                            ),
                            "pointsAwarded": JSONSchema(
                                type: .array,
                                items: JSONSchema(
                                    type: .object,
                                    properties: [
                                        "model": JSONSchema(
                                            type: .string,
                                            description: "Name of the model"
                                        ),
                                        "points": JSONSchema(
                                            type: .integer,
                                            description: "Points awarded by this model"
                                        )
                                    ],
                                    required: ["model", "points"],
                                    additionalProperties: false
                                )
                            ),
                            "modelVotes": JSONSchema(
                                type: .array,
                                items: JSONSchema(
                                    type: .object,
                                    properties: [
                                        "model": JSONSchema(
                                            type: .string,
                                            description: "Name of the model"
                                        ),
                                        "votedForLetterId": JSONSchema(
                                            type: .string,
                                            description: "UUID of the letter this model voted for"
                                        )
                                    ],
                                    required: ["model", "votedForLetterId"],
                                    additionalProperties: false
                                )
                            )
                        ],
                        required: ["summaryOfModelAnalysis", "pointsAwarded", "modelVotes"],
                        additionalProperties: false
                    )
                )
            ],
            required: ["letterAnalyses"],
            additionalProperties: false
        )
    }
}
