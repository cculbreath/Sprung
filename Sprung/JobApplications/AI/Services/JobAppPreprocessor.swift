//
//  JobAppPreprocessor.swift
//  Sprung
//
//  Service for preprocessing job applications in the background.
//  Extracts requirements from job descriptions and identifies relevant knowledge cards.
//
//  This runs automatically after a job is created, storing results on the JobApp
//  for instant access during resume customization.
//

import Foundation
import SwiftData
import SwiftOpenAI

/// Service for preprocessing job applications in the background
/// Extracts requirements and identifies relevant knowledge cards
@MainActor
class JobAppPreprocessor {
    // MARK: - JSON Schema for Structured Output

    /// Schema for preprocessing response - required for Gemini via OpenRouter
    private static let preprocessingSchema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Job requirements extraction and card relevance analysis",
            properties: [
                "must_have": JSONSchema(
                    type: .array,
                    description: "Explicitly required skills/experience (deal-breakers)",
                    items: JSONSchema(type: .string)
                ),
                "strong_signal": JSONSchema(
                    type: .array,
                    description: "Emphasized or frequently mentioned requirements",
                    items: JSONSchema(type: .string)
                ),
                "preferred": JSONSchema(
                    type: .array,
                    description: "Nice-to-have qualifications",
                    items: JSONSchema(type: .string)
                ),
                "cultural": JSONSchema(
                    type: .array,
                    description: "Soft skills and cultural fit indicators",
                    items: JSONSchema(type: .string)
                ),
                "ats_keywords": JSONSchema(
                    type: .array,
                    description: "Technical terms and keywords for ATS matching",
                    items: JSONSchema(type: .string)
                ),
                "relevant_card_ids": JSONSchema(
                    type: .array,
                    description: "IDs of knowledge cards relevant to this job",
                    items: JSONSchema(type: .string)
                )
            ],
            required: ["must_have", "strong_signal", "preferred", "cultural", "ats_keywords", "relevant_card_ids"],
            additionalProperties: false
        )
    }()

    /// Schema for skill matching response (second LLM call)
    private static let skillMatchingSchema: JSONSchema = {
        let skillRecommendationSchema = JSONSchema(
            type: .object,
            description: "A skill the user likely has based on existing expertise",
            properties: [
                "skill_name": JSONSchema(type: .string, description: "The job requirement skill they likely have"),
                "category": JSONSchema(type: .string, description: "Skill category name"),
                "confidence": JSONSchema(type: .string, description: "high, medium, or low"),
                "reason": JSONSchema(type: .string, description: "Why this skill is inferred"),
                "related_user_skills": JSONSchema(type: .array, description: "User skills suggesting this", items: JSONSchema(type: .string)),
                "source_card_ids": JSONSchema(type: .array, description: "KC UUIDs evidencing this", items: JSONSchema(type: .string))
            ],
            required: ["skill_name", "category", "confidence", "reason", "related_user_skills", "source_card_ids"]
        )

        // Note: We only ask for text snippets, not character indices.
        // Character positions are computed programmatically after LLM response.
        let skillEvidenceSchema = JSONSchema(
            type: .object,
            description: "A skill found in the job description with text evidence",
            properties: [
                "skill_name": JSONSchema(type: .string, description: "Normalized skill name"),
                "category": JSONSchema(type: .string, description: "matched, recommended, or unmatched"),
                "evidence_texts": JSONSchema(type: .array, description: "Exact text snippets from job description where this skill is mentioned", items: JSONSchema(type: .string)),
                "matched_skill_id": JSONSchema(type: .string, description: "UUID of matched user skill if category is matched, empty string otherwise")
            ],
            required: ["skill_name", "category", "evidence_texts", "matched_skill_id"]
        )

        return JSONSchema(
            type: .object,
            description: "Skill matching, inference, and text evidence extraction",
            properties: [
                "matched_skill_ids": JSONSchema(
                    type: .array,
                    description: "UUIDs of user skills that match job requirements",
                    items: JSONSchema(type: .string)
                ),
                "skill_recommendations": JSONSchema(
                    type: .array,
                    description: "Skills the user likely has based on existing expertise",
                    items: skillRecommendationSchema
                ),
                "skill_evidence": JSONSchema(
                    type: .array,
                    description: "All skills found in job description with text locations for highlighting",
                    items: skillEvidenceSchema
                )
            ],
            required: ["matched_skill_ids", "skill_recommendations", "skill_evidence"],
            additionalProperties: false
        )
    }()
    // MARK: - Dependencies

    private weak var llmFacade: LLMFacade?
    private weak var skillStore: SkillStore?
    private weak var activityTracker: BackgroundActivityTracker?

    // MARK: - Concurrency Control

    /// Semaphore to limit concurrent preprocessing jobs
    private let concurrencyLimit = 8
    private var activeJobCount = 0
    private var pendingJobs: [(jobApp: JobApp, cards: [KnowledgeCard], context: ModelContext)] = []

    // MARK: - Configuration

    /// Model for preprocessing (user-configurable via Settings)
    /// Returns nil if not configured; callers must validate before use
    private var preprocessingModel: String? {
        let modelId = UserDefaults.standard.string(forKey: "backgroundProcessingModelId")
        return (modelId?.isEmpty == false) ? modelId : nil
    }

    // MARK: - Initialization

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("🔧 JobAppPreprocessor initialized", category: .ai)
    }

    /// Set the skill store for skill matching during preprocessing
    func setSkillStore(_ skillStore: SkillStore) {
        self.skillStore = skillStore
    }

    /// Set the activity tracker for reporting preprocessing progress
    func setActivityTracker(_ tracker: BackgroundActivityTracker) {
        self.activityTracker = tracker
    }

    // MARK: - Public API

    /// Preprocess a job application: extract requirements and identify relevant cards
    /// - Parameters:
    ///   - jobApp: The job application to preprocess
    ///   - allCards: All available knowledge cards
    ///   - modelContext: SwiftData context for saving
    func preprocessInBackground(
        for jobApp: JobApp,
        allCards: [KnowledgeCard],
        modelContext: ModelContext
    ) {
        // Queue the job
        pendingJobs.append((jobApp: jobApp, cards: allCards, context: modelContext))
        processNextJobIfAvailable()
    }

    // MARK: - Concurrency Management

    private func processNextJobIfAvailable() {
        guard activeJobCount < concurrencyLimit,
              !pendingJobs.isEmpty else {
            return
        }

        let job = pendingJobs.removeFirst()
        activeJobCount += 1

        // Create operation ID for tracking
        let operationId = UUID().uuidString
        let operationName = "\(job.jobApp.companyName): \(job.jobApp.jobPosition)"

        // Start tracking this operation
        activityTracker?.trackOperation(
            id: operationId,
            type: .preprocessing,
            name: operationName
        )

        Task {
            defer {
                Task { @MainActor in
                    self.activeJobCount -= 1
                    self.processNextJobIfAvailable()
                }
            }

            do {
                let result = try await preprocess(
                    jobDescription: job.jobApp.jobDescription,
                    cards: job.cards,
                    operationId: operationId
                )

                job.jobApp.extractedRequirements = result.requirements
                job.jobApp.relevantCardIds = result.relevantCardIds
                try? job.context.save()

                await MainActor.run {
                    activityTracker?.markCompleted(operationId: operationId)
                }
                Logger.info("✅ [JobAppPreprocessor] Preprocessed: \(job.jobApp.jobPosition) at \(job.jobApp.companyName)", category: .ai)
            } catch {
                await MainActor.run {
                    activityTracker?.markFailed(operationId: operationId, error: error.localizedDescription)
                }
                Logger.error("❌ [JobAppPreprocessor] Failed to preprocess \(job.jobApp.jobPosition): \(error.localizedDescription)", category: .ai)
            }
        }
    }

    // MARK: - Private

    private func preprocess(
        jobDescription: String,
        cards: [KnowledgeCard],
        operationId: String
    ) async throws -> PreprocessingResult {
        guard let facade = llmFacade else {
            throw PreprocessingError.llmNotAvailable
        }

        guard let modelId = preprocessingModel, !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "backgroundProcessingModelId",
                operationName: "Job Requirements Extraction"
            )
        }

        // Phase 1: Requirements Extraction
        await MainActor.run {
            activityTracker?.updatePhase(operationId: operationId, phase: "Requirements Extraction")
            activityTracker?.appendTranscript(
                operationId: operationId,
                entryType: .system,
                content: "Starting requirements extraction",
                details: "Model: \(modelId), Cards: \(cards.count)"
            )
        }

        // Build enriched card summaries with technologies and domains
        let cardSummaries = cards.map { card -> String in
            var summary = "- [\(card.id.uuidString)]: \(card.title)"
            if !card.technologies.isEmpty {
                summary += "\n  Technologies: \(card.technologies.joined(separator: ", "))"
            }
            if !card.extractable.domains.isEmpty {
                summary += "\n  Domains: \(card.extractable.domains.joined(separator: ", "))"
            }
            return summary
        }.joined(separator: "\n")

        let prompt = """
        Analyze this job posting and identify:
        1. Requirements by priority tier
        2. Which knowledge cards are relevant to this job

        JOB POSTING:
        \(jobDescription)

        AVAILABLE KNOWLEDGE CARDS:
        \(cardSummaries)

        ---

        TASK 1 - REQUIREMENTS:
        Extract requirements into these categories:
        - must_have: Explicitly required, deal-breakers (e.g., "required", "must have", "X years experience")
        - strong_signal: Emphasized or mentioned multiple times
        - preferred: Nice-to-have, mentioned once (e.g., "preferred", "bonus", "plus")
        - cultural: Soft skills, team fit, work style expectations
        - ats_keywords: ALL technical terms, tools, technologies for keyword matching

        TASK 2 - RELEVANT CARDS:
        From the card list above, identify which cards are likely relevant to this job.
        Be INCLUSIVE — when in doubt, include the card. It's better to include a
        marginally relevant card than exclude a useful one.

        Return JSON matching the required structure.
        """

        await MainActor.run {
            activityTracker?.appendTranscript(
                operationId: operationId,
                entryType: .llmRequest,
                content: "Sending requirements extraction request",
                details: "Prompt length: \(prompt.count) chars"
            )
        }

        let response = try await facade.executeStructuredWithSchema(
            prompt: prompt,
            modelId: modelId,
            as: PreprocessingResponse.self,
            schema: Self.preprocessingSchema,
            schemaName: "preprocessing_response",
            temperature: 0.2,
            backend: .openRouter
        )

        await MainActor.run {
            activityTracker?.appendTranscript(
                operationId: operationId,
                entryType: .llmResponse,
                content: "Extracted \(response.mustHave.count) must-have, \(response.strongSignal.count) strong-signal, \(response.atsKeywords.count) ATS keywords",
                details: "Relevant cards: \(response.relevantCardIds.count)"
            )
        }

        // Second call: Skill matching and inference (only if skill store available)
        var matchedSkillIds: [String] = []
        var skillRecommendations: [SkillRecommendation] = []
        var skillEvidence: [JobSkillEvidence] = []

        if let skillStore = skillStore {
            let skills = await MainActor.run { skillStore.skills }
            if !skills.isEmpty {
                await MainActor.run {
                    activityTracker?.updatePhase(operationId: operationId, phase: "Skill Matching")
                    activityTracker?.appendTranscript(
                        operationId: operationId,
                        entryType: .system,
                        content: "Starting skill matching",
                        details: "User skills: \(skills.count), ATS keywords: \(response.atsKeywords.count)"
                    )
                }

                let skillResult = try await inferSkills(
                    jobDescription: jobDescription,
                    atsKeywords: response.atsKeywords,
                    skills: skills,
                    cards: cards,
                    relevantCardIds: response.relevantCardIds,
                    facade: facade,
                    modelId: modelId,
                    operationId: operationId
                )
                matchedSkillIds = skillResult.matchedSkillIds
                skillRecommendations = skillResult.skillRecommendations.map { $0.toModel() }
                skillEvidence = skillResult.skillEvidence.map { $0.toModel(jobDescription: jobDescription) }

                await MainActor.run {
                    activityTracker?.appendTranscript(
                        operationId: operationId,
                        entryType: .llmResponse,
                        content: "Matched \(matchedSkillIds.count) skills, \(skillRecommendations.count) recommendations",
                        details: nil
                    )
                }
            }
        }

        return PreprocessingResult(
            requirements: ExtractedRequirements(
                mustHave: response.mustHave,
                strongSignal: response.strongSignal,
                preferred: response.preferred,
                cultural: response.cultural,
                atsKeywords: response.atsKeywords,
                extractedAt: Date(),
                extractionModel: modelId,
                matchedSkillIds: matchedSkillIds,
                skillRecommendations: skillRecommendations,
                skillEvidence: skillEvidence
            ),
            relevantCardIds: response.relevantCardIds
        )
    }

    // MARK: - Skill Inference (Second LLM Call)

    private func inferSkills(
        jobDescription: String,
        atsKeywords: [String],
        skills: [Skill],
        cards: [KnowledgeCard],
        relevantCardIds: [String],
        facade: LLMFacade,
        modelId: String,
        operationId: String
    ) async throws -> SkillMatchingResponse {
        // Build skill bank summary
        let skillSummaries = skills.map { skill -> String in
            var line = "[\(skill.id.uuidString)]: \(skill.canonical) (\(skill.category))"
            if !skill.atsVariants.isEmpty {
                line += " - variants: \(skill.atsVariants.joined(separator: ", "))"
            }
            return line
        }.joined(separator: "\n")

        // Build relevant cards summary (enriched)
        let relevantCards = cards.filter { relevantCardIds.contains($0.id.uuidString) }
        let relevantCardSummaries = relevantCards.map { card -> String in
            var summary = "[\(card.id.uuidString)]: \(card.title)"
            if !card.technologies.isEmpty {
                summary += "\n  Technologies: \(card.technologies.joined(separator: ", "))"
            }
            if !card.extractable.domains.isEmpty {
                summary += "\n  Domains: \(card.extractable.domains.joined(separator: ", "))"
            }
            return summary
        }.joined(separator: "\n")

        let prompt = """
        Match user skills to job requirements, identify adjacent skills, and extract text evidence.

        JOB DESCRIPTION:
        \(jobDescription)

        JOB REQUIREMENTS (ATS Keywords):
        \(atsKeywords.joined(separator: ", "))

        USER'S SKILL BANK:
        \(skillSummaries)

        RELEVANT KNOWLEDGE CARDS (evidence of experience):
        \(relevantCardSummaries)

        ---

        TASK 1 - SKILL MATCHING:
        Identify which skills from the user's skill bank match the job requirements.
        Consider both exact matches and semantic equivalents (e.g., "Python" matches "python3").
        Return their UUIDs in matched_skill_ids.

        TASK 2 - ADJACENT SKILL INFERENCE:
        Identify skills from the job requirements that the user likely has but hasn't explicitly listed.
        Base these on:
        1. Domain adjacency: If user has skills A and B in a domain, they likely have related skill C
        2. Technology ecosystem: Skills often cluster (e.g., welding → flame cutting, SQL → database design)
        3. KnowledgeCard evidence: Technologies/domains in cards suggest related capabilities

        For each suggested skill:
        - skill_name: The job requirement skill they likely have
        - category: Appropriate skill category (e.g. Programming Languages, Frameworks & Libraries, Tools & Platforms, Hardware & Electronics, Fabrication & Manufacturing, Scientific & Analysis, Methodologies & Processes, Writing & Communication, Research Methods, Regulatory & Compliance, Leadership & Management, Domain Expertise, or other domain-specific category)
        - confidence: "high" if multiple signals, "medium" if single strong signal, "low" if plausible inference
        - reason: Brief explanation of why this is inferred
        - related_user_skills: User's existing skill names that suggest this capability
        - source_card_ids: KnowledgeCard UUIDs supporting this inference

        Only suggest skills that MATCH JOB REQUIREMENTS. Don't suggest random related skills.

        TASK 3 - TEXT EVIDENCE EXTRACTION:
        For EVERY skill mentioned in the ATS keywords, find where it appears in the job description.
        For each skill, provide:
        - skill_name: The skill name (normalized)
        - category: "matched" if user has it, "recommended" if in skill_recommendations, "unmatched" if neither
        - evidence_texts: Array of EXACT text snippets copied verbatim from the job description where this skill is mentioned
        - matched_skill_id: UUID of the user's skill if category is "matched", otherwise empty string ""

        IMPORTANT for evidence_texts:
        - Copy text EXACTLY as it appears in the job description (preserve case, spacing, punctuation)
        - Include enough context to be meaningful (short phrases or partial sentences, not just single words)
        - Include all distinct mentions of each skill

        Return JSON matching the required structure.
        """

        await MainActor.run {
            activityTracker?.appendTranscript(
                operationId: operationId,
                entryType: .llmRequest,
                content: "Sending skill matching request",
                details: "Prompt length: \(prompt.count) chars"
            )
        }

        return try await facade.executeStructuredWithSchema(
            prompt: prompt,
            modelId: modelId,
            as: SkillMatchingResponse.self,
            schema: Self.skillMatchingSchema,
            schemaName: "skill_matching_response",
            temperature: 0.2,
            backend: .openRouter
        )
    }
}

// MARK: - Response Types

private struct PreprocessingResponse: Codable, Sendable {
    let mustHave: [String]
    let strongSignal: [String]
    let preferred: [String]
    let cultural: [String]
    let atsKeywords: [String]
    let relevantCardIds: [String]

    enum CodingKeys: String, CodingKey {
        case mustHave = "must_have"
        case strongSignal = "strong_signal"
        case preferred
        case cultural
        case atsKeywords = "ats_keywords"
        case relevantCardIds = "relevant_card_ids"
    }
}

private struct SkillMatchingResponse: Codable, Sendable {
    let matchedSkillIds: [String]
    let skillRecommendations: [SkillRecommendationResponse]
    let skillEvidence: [SkillEvidenceResponse]

    enum CodingKeys: String, CodingKey {
        case matchedSkillIds = "matched_skill_ids"
        case skillRecommendations = "skill_recommendations"
        case skillEvidence = "skill_evidence"
    }
}

private struct SkillEvidenceResponse: Codable, Sendable {
    let skillName: String
    let category: String
    let evidenceTexts: [String]  // Exact text snippets from job description
    let matchedSkillId: String   // Required by schema, empty string when not matched

    enum CodingKeys: String, CodingKey {
        case skillName = "skill_name"
        case category
        case evidenceTexts = "evidence_texts"
        case matchedSkillId = "matched_skill_id"
    }

    /// Convert to model, computing actual character positions by searching the job description
    func toModel(jobDescription: String) -> JobSkillEvidence {
        // Find actual positions of each evidence text in the job description
        let spans = evidenceTexts.flatMap { searchText -> [TextSpan] in
            findAllOccurrences(of: searchText, in: jobDescription)
        }

        return JobSkillEvidence(
            skillName: skillName,
            category: JobSkillCategory(rawValue: category) ?? .unmatched,
            evidenceSpans: spans,
            matchedSkillId: matchedSkillId.isEmpty ? nil : matchedSkillId
        )
    }

    /// Find all occurrences of a text snippet in the job description (case-insensitive)
    private func findAllOccurrences(of searchText: String, in text: String) -> [TextSpan] {
        var spans: [TextSpan] = []
        let lowerText = text.lowercased()
        let lowerSearch = searchText.lowercased()

        var searchStart = lowerText.startIndex
        while let range = lowerText.range(of: lowerSearch, range: searchStart..<lowerText.endIndex) {
            let start = lowerText.distance(from: lowerText.startIndex, to: range.lowerBound)
            let end = lowerText.distance(from: lowerText.startIndex, to: range.upperBound)
            // Get the actual text from the original (preserving case)
            let actualText = String(text[range])
            spans.append(TextSpan(start: start, end: end, text: actualText))
            searchStart = range.upperBound
        }

        return spans
    }
}

private struct SkillRecommendationResponse: Codable, Sendable {
    let skillName: String
    let category: String
    let confidence: String
    let reason: String
    let relatedUserSkills: [String]
    let sourceCardIds: [String]

    enum CodingKeys: String, CodingKey {
        case skillName = "skill_name"
        case category
        case confidence
        case reason
        case relatedUserSkills = "related_user_skills"
        case sourceCardIds = "source_card_ids"
    }

    func toModel() -> SkillRecommendation {
        SkillRecommendation(
            skillName: skillName,
            category: category,
            confidence: confidence,
            reason: reason,
            relatedUserSkills: relatedUserSkills,
            sourceCardIds: sourceCardIds
        )
    }
}

private struct PreprocessingResult {
    let requirements: ExtractedRequirements
    let relevantCardIds: [String]
}

// MARK: - Errors

enum PreprocessingError: LocalizedError {
    case llmNotAvailable
    case emptyJobDescription

    var errorDescription: String? {
        switch self {
        case .llmNotAvailable:
            return "LLM service is not available for preprocessing"
        case .emptyJobDescription:
            return "Job description is empty"
        }
    }
}
