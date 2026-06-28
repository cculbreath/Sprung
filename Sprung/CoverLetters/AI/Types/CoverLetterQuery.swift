//
//  CoverLetterQuery.swift
//  Sprung
//
//  Created on 6/5/2025
//
//  Centralized prompt and schema management for cover letter operations
import Foundation
import SwiftUI
// MARK: - Cover Letter Response Types
/// Voting scheme for multi-model selection
enum VotingScheme: String, CaseIterable {
    case firstPastThePost = "First Past The Post"
    case scoreVoting = "Score Voting (20 points)"
    var description: String {
        switch self {
        case .firstPastThePost:
            return "Each model votes for one favorite letter"
        case .scoreVoting:
            return "Each model allocates 20 points among all letters"
        }
    }
}
/// Score allocation for a single cover letter in score voting
struct CoverLetterScore: Codable {
    let letterUuid: String
    let score: Int
    let reasoning: String?  // Optional reasoning field
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        letterUuid = try container.decode(String.self, forKey: .letterUuid)
        score = try container.decode(Int.self, forKey: .score)
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
    }
    enum CodingKeys: String, CodingKey {
        case letterUuid, score, reasoning
    }
}
/// Response schema for best cover letter selection
struct BestCoverLetterResponse: Codable {
    let strengthAndVoiceAnalysis: String
    let bestLetterUuid: String?  // Optional: Used only for FPTP voting
    let verdict: String
    let scoreAllocations: [CoverLetterScore]?  // Optional: Used only for score voting
    // Coding keys to handle optional fields gracefully
    enum CodingKeys: String, CodingKey {
        case strengthAndVoiceAnalysis
        case bestLetterUuid
        case verdict
        case scoreAllocations
    }
    // Custom decoder to handle missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strengthAndVoiceAnalysis = try container.decode(String.self, forKey: .strengthAndVoiceAnalysis)
        verdict = try container.decode(String.self, forKey: .verdict)
        // Try to decode bestLetterUuid, but allow it to be missing
        bestLetterUuid = try container.decodeIfPresent(String.self, forKey: .bestLetterUuid)
        // Try to decode scoreAllocations, but allow it to be missing
        scoreAllocations = try container.decodeIfPresent([CoverLetterScore].self, forKey: .scoreAllocations)
    }
}
/// Errors thrown while assembling cover letter prompts.
enum CoverLetterQueryError: LocalizedError {
    case resumeContextUnavailable(underlying: String)

    var errorDescription: String? {
        switch self {
        case .resumeContextUnavailable(let underlying):
            return "Unable to build the resume context for the cover letter prompt: \(underlying)"
        }
    }

    var recoverySuggestion: String? {
        "Verify the selected resume renders correctly in the Resume tab, then try again."
    }
}

@Observable class CoverLetterQuery {
    // MARK: - Properties
    /// Set this to `true` if you want to save a debug file containing the prompt text.
    var saveDebugPrompt: Bool = false
    /// Non-nil when the resume context was too large for the prompt and was trimmed.
    /// Callers and views should surface this so users know the letter was generated on a partial resume.
    private(set) var resumeContextTruncationWarning: String? = nil
    // MARK: - JSON Schemas
    /// Schema for best cover letter selection (FPTP voting)
    static let bestCoverLetterSchemaString = """
    {
        "type": "object",
        "properties": {
            "strengthAndVoiceAnalysis": {
                "type": "string",
                "description": "Comprehensive assessment of each letter's strength and voice covering all evaluated letters"
            },
            "bestLetterUuid": {
                "type": "string",
                "description": "UUID of the selected best cover letter"
            },
            "verdict": {
                "type": "string",
                "description": "Reason for the ultimate choice"
            }
        },
        "required": ["strengthAndVoiceAnalysis", "bestLetterUuid", "verdict"],
        "additionalProperties": false
    }
    """
    /// Schema for score voting cover letter selection
    static let scoreVotingSchemaString = """
    {
        "type": "object",
        "properties": {
            "strengthAndVoiceAnalysis": {
                "type": "string",
                "description": "Comprehensive assessment of each letter's strengths covering all evaluated letters"
            },
            "scoreAllocations": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "letterUuid": {
                            "type": "string",
                            "description": "UUID of the cover letter"
                        },
                        "score": {
                            "type": "integer",
                            "description": "Points allocated to this letter (total must equal 20)"
                        }
                    },
                    "required": ["letterUuid", "score"],
                    "additionalProperties": false
                }
            },
            "verdict": {
                "type": "string",
                "description": "Explanation of point allocation"
            }
        },
        "required": ["strengthAndVoiceAnalysis", "scoreAllocations", "verdict"],
        "additionalProperties": false
    }
    """
    // MARK: - Core Data
    var applicant: Applicant
   let coverLetter: CoverLetter
   let resume: Resume
   let jobApp: JobApp
    private static let maxResumeContextBytes = 120_000
    // MARK: - Derived Properties
    var jobListing: String {
        return jobApp.jobListingString
    }
    /// Builds the resume context for the prompt. Throws when no usable
    /// resume text exists — cover letters must never be generated against an
    /// empty RESUME CONTEXT.
    func resumeContext() throws -> String {
        if !resume.textResume.isEmpty {
            return resume.textResume
        }
        let string: String
        do {
            let context = try ResumeTemplateDataBuilder.buildContext(from: resume)
            let data = try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted])
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw CoverLetterQueryError.resumeContextUnavailable(
                    underlying: "Resume context could not be encoded as UTF-8 text."
                )
            }
            string = encoded
        } catch let error as CoverLetterQueryError {
            throw error
        } catch {
            throw CoverLetterQueryError.resumeContextUnavailable(underlying: error.localizedDescription)
        }
        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoverLetterQueryError.resumeContextUnavailable(
                underlying: "The resume produced no content."
            )
        }
        let byteCount = string.utf8.count
        guard byteCount > Self.maxResumeContextBytes else {
            resumeContextTruncationWarning = nil
            return string
        }
        Logger.warning("CoverLetterQuery: resume context is \(byteCount) bytes; truncating to \(Self.maxResumeContextBytes) bytes to avoid prompt overflow.")
        resumeContextTruncationWarning = "Resume was too large to include in full — the cover letter was generated from a partial resume (\(byteCount / 1_000)k bytes, trimmed to \(Self.maxResumeContextBytes / 1_000)k). Consider reducing resume length."
        let truncated = truncateContext(string, maxBytes: Self.maxResumeContextBytes)
        return truncated + "\n\n/* truncated resume context to fit cover letter prompt */"
    }
    let knowledgeCards: [KnowledgeCard]
    let dossierContext: String?

    var knowledgeCardDocs: String {
        if knowledgeCards.isEmpty {
            return ""
        }
        return knowledgeCards.map { $0.title + ":\n" + $0.narrative + "\n\n" }.joined()
    }
    let writersVoice: String
    private func truncateContext(_ string: String, maxBytes: Int) -> String {
        var count = 0
        var index = string.startIndex
        while index < string.endIndex {
            let character = string[index]
            let characterBytes = character.utf8.count
            if count + characterBytes > maxBytes {
                break
            }
            count += characterBytes
            index = string.index(after: index)
        }
        var truncated = String(string[string.startIndex..<index])
        if truncated.last?.isWhitespace == false {
            truncated.append(" ")
        }
        truncated.append(contentsOf: "...")
        return truncated
    }
    // MARK: - Initialization
    private let exportCoordinator: ResumeExportCoordinator
    init(
        coverLetter: CoverLetter,
        resume: Resume,
        jobApp: JobApp,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfile: ApplicantProfile,
        writersVoice: String,
        knowledgeCards: [KnowledgeCard] = [],
        dossierContext: String? = nil,
        saveDebugPrompt: Bool = false
    ) {
        self.coverLetter = coverLetter
        self.resume = resume
        self.jobApp = jobApp
        self.writersVoice = writersVoice
        self.knowledgeCards = knowledgeCards
        self.dossierContext = dossierContext
        self.saveDebugPrompt = saveDebugPrompt
        self.exportCoordinator = exportCoordinator
        applicant = Applicant(profile: applicantProfile)
    }
    // MARK: - Shared Prompt Blocks
    /// Anti-fabrication and register constraints applied to every prompt that
    /// produces employer-facing prose. Ported from the SGM reference
    /// generators (ObjectiveGenerator).
    private var constraintsBlock: String {
        """
        CONSTRAINTS:
        1. Use ONLY facts from the job listing, resume context, and background documents provided
        2. Do NOT invent metrics, percentages, or quantitative claims — any number in the letter must appear verbatim in the provided materials
        3. Do NOT claim skills, credentials, or experiences that are not documented above
        4. Match the candidate's writing voice — study the writing style reference carefully
        5. Avoid generic cover letter phrases

        FORBIDDEN:
        - Fabricated numbers ("X years of experience", "improved by Y%")
        - Generic phrases ("results-driven", "passionate about", "proven track record")
        - Vague claims ("significantly improved", "extensive experience")
        - LinkedIn buzzwords ("leveraged", "spearheaded", "synergized")
        """
    }

    /// Output-format rules shared by generation and revision prompts.
    private var formatBlock: String {
        """
        FORMAT:
        - Return ONLY the body text of the letter: no date, address, salutation, closing, signature, or contact information
        - Start immediately with the first paragraph and end with the final paragraph
        - Block-format paragraphs with no indentation; a single newline at the end of each paragraph; no blank lines between paragraphs
        - Plain text only: no markdown, no JSON, no commentary or explanations
        """
    }

    // MARK: - Cover Letter Prompts
    /// Self-contained prompt for cover letter generation.
    @MainActor
    func generationPrompt() async throws -> String {
        // Ensure resume text is fresh; a stale or failed render must surface,
        // never silently produce a letter with no resume context.
        try await exportCoordinator.ensureFreshRenderedText(for: resume)
        let resumeContextText = try resumeContext()
        var sections = """
        You are a professional writer drafting a cover letter on behalf of \(applicant.name). \
        Write grounded, specific prose in the candidate's own voice, based strictly on the documented evidence below.
        ================================================================================
        COVER LETTER GENERATION REQUEST
        ================================================================================
        GOAL:
        Write the body of a cover letter for \(applicant.name)'s application for the following position:
        JOB LISTING:
        \(jobListing)
        RESUME CONTEXT:
        \(resumeContextText)
        """
        if !knowledgeCardDocs.isEmpty {
            sections += """

            BACKGROUND DOCUMENTS:
            \(knowledgeCardDocs)
            """
        }
        if let dossier = dossierContext, !dossier.isEmpty {
            sections += """

            CANDIDATE CONTEXT:
            \(dossier)
            """
        }
        if !writersVoice.isEmpty {
            sections += """

            WRITING STYLE REFERENCE:
            \(writersVoice)
            """
        }
        sections += """

        INSTRUCTIONS:
        - Tailor the letter to the job listing, connecting the candidate's documented experience to the role's actual requirements
        - Be specific: ground every claim in named projects, technologies, and accomplishments from the resume and background documents
        - Reflect the candidate's authentic voice as shown in the writing style reference
        - Keep the tone professional and direct

        \(constraintsBlock)

        \(formatBlock)
        ================================================================================
        """
        let prompt = sections
        if saveDebugPrompt {
            savePromptToDownloads(content: prompt, fileName: "coverLetterGenerationPrompt.txt")
        }
        return prompt
    }
    /// Self-contained prompt for cover letter revision. Every revision request
    /// carries the full job/resume/voice context plus the current draft, so it
    /// is deterministic and independent of any prior conversation state.
    @MainActor
    func revisionPrompt(
        feedback: String,
        editorPrompt: CoverLetterPrompts.EditorPrompts = .improve
    ) async throws -> String {
        try await exportCoordinator.ensureFreshRenderedText(for: resume)
        let resumeContextText = try resumeContext()
        let instruction: String
        if editorPrompt == .custom {
            instruction = """
            \(editorPrompt.rawValue)
            \(feedback)
            """
        } else {
            instruction = editorPrompt.rawValue
        }
        var sections = """
        You are a professional writer revising a cover letter on behalf of \(applicant.name). \
        Produce grounded, specific prose in the candidate's own voice, based strictly on the documented evidence below.
        ================================================================================
        COVER LETTER REVISION REQUEST
        ================================================================================
        The letter accompanies \(applicant.name)'s application for the following position:
        JOB LISTING:
        \(jobListing)
        RESUME CONTEXT:
        \(resumeContextText)
        """
        if !writersVoice.isEmpty {
            sections += """

            WRITING STYLE REFERENCE:
            \(writersVoice)
            """
        }
        sections += """

        CURRENT DRAFT:
        \(coverLetter.content)

        REVISION INSTRUCTIONS:
        \(instruction)

        \(constraintsBlock)

        \(formatBlock)
        ================================================================================
        """
        let prompt = sections
        if saveDebugPrompt {
            savePromptToDownloads(content: prompt, fileName: "coverLetterRevisionPrompt.txt")
        }
        return prompt
    }
    // MARK: - Best Cover Letter Selection Prompts
    /// Generate prompt for best cover letter evaluation
    func bestCoverLetterPrompt(
        coverLetters: [CoverLetter],
        votingScheme: VotingScheme,
        includeJSONInstructions: Bool = false
    ) -> String {
        let schemeInstructions = votingScheme == .firstPastThePost ?
            "Select the single best cover letter and return its UUID in the bestLetterUuid field." :
            "Allocate exactly 20 points among all cover letters based on quality. Use the scoreAllocations field."
        var prompt = """
        You are an expert career advisor and professional writer specializing in evaluating cover letters. Your task is to analyze a list of cover letters for a specific job application and \(schemeInstructions)
        Job Details:
        - Position: \(jobApp.jobPosition)
        - Company: \(jobApp.companyName)
        - Job Description: \(jobApp.jobDescription)
        Writing Samples (Candidate's Style):
        \(writersVoice)
        Cover Letters to Evaluate:
        """
        for letter in coverLetters {
            prompt += """
            \(letter.id.uuidString):
            Content: \(letter.content)
            """
        }
        if votingScheme == .firstPastThePost {
            prompt += """
            Select the single best cover letter based on:
            - Voice: How well does the letter reflect the candidate's authentic self?
            - Style: Does the style align with the candidate's writing samples?
            - Quality: Grammar, coherence, impact, and relevancy to the job description.
            """
            if includeJSONInstructions {
                prompt += """
                CRITICAL JSON FORMATTING REQUIREMENTS:
                - You must respond with valid JSON only
                - Do not include any text before or after the JSON object
                - Use double quotes for all strings
                - Ensure all required fields are present
                - Follow the exact schema structure below
                Required JSON Schema:
                """
                prompt += Self.bestCoverLetterSchemaString
                prompt += """
                Return your selection as JSON following this exact format:
                """
            } else {
                prompt += """
                Return your selection as JSON:
                """
            }
            prompt += """
            {
                "strengthAndVoiceAnalysis": "Comprehensive assessment of each letter's strengths and weaknesses. Provide specific commentary for every evaluated letter including voice, style, and quality analysis",
                "bestLetterUuid": "UUID of the selected best cover letter",
                "verdict": "Reason for your choice"
            }
            """
        } else {
            prompt += """
            Allocate exactly 20 points among these cover letters based on:
            - Voice: How well does the letter reflect the candidate's authentic self?
            - Style: Does the style align with the candidate's writing samples?
            - Quality: Grammar, coherence, impact, and relevancy to the job description.
            """
            if includeJSONInstructions {
                prompt += """
                CRITICAL JSON FORMATTING REQUIREMENTS:
                - You must respond with valid JSON only
                - Do not include any text before or after the JSON object
                - Use double quotes for all strings
                - Ensure all required fields are present
                - The total points must equal exactly 20
                - Follow the exact schema structure below
                Required JSON Schema:
                """
                prompt += Self.scoreVotingSchemaString
                prompt += """
                Return your allocation as JSON following this exact format:
                """
            } else {
                prompt += """
                Return your allocation as JSON:
                """
            }
            prompt += """
            {
                "strengthAndVoiceAnalysis": "Comprehensive assessment of each letter's strengths and weaknesses. Provide commentary for every evaluated letter",
                "scoreAllocations": [
                    {"letterUuid": "UUID", "score": 0}
                ],
                "verdict": "Explanation of your point allocation"
            }
            IMPORTANT: The total points must equal exactly 20.
            """
        }
        if saveDebugPrompt {
            savePromptToDownloads(content: prompt, fileName: "bestCoverLetterPrompt.txt")
        }
        return prompt
    }
    /// Get JSON schema for the specified voting scheme
    static func getJSONSchema(for votingScheme: VotingScheme) -> JSONSchema? {
        if votingScheme == .firstPastThePost {
            // FPTP schema
            return JSONSchema(
                type: .object,
                properties: [
                    "strengthAndVoiceAnalysis": JSONSchema(
                        type: .string,
                        description: "Comprehensive assessment of each letter's strength and voice covering all evaluated letters"
                    ),
                    "bestLetterUuid": JSONSchema(
                        type: .string,
                        description: "UUID of the selected best cover letter"
                    ),
                    "verdict": JSONSchema(
                        type: .string,
                        description: "Reason for the ultimate choice"
                    )
                ],
                required: ["strengthAndVoiceAnalysis", "bestLetterUuid", "verdict"],
                additionalProperties: false
            )
        } else {
            // Score voting schema
            return JSONSchema(
                type: .object,
                properties: [
                    "strengthAndVoiceAnalysis": JSONSchema(
                        type: .string,
                        description: "Comprehensive assessment of each letter's strengths and weaknesses covering all evaluated letters"
                    ),
                    "scoreAllocations": JSONSchema(
                        type: .array,
                        items: JSONSchema(
                            type: .object,
                            properties: [
                                "letterUuid": JSONSchema(
                                    type: .string,
                                    description: "UUID of the cover letter"
                                ),
                                "score": JSONSchema(
                                    type: .integer,
                                    description: "Points allocated to this letter (total must equal 20)"
                                )
                            ],
                            required: ["letterUuid", "score"],
                            additionalProperties: false
                        )
                    ),
                    "verdict": JSONSchema(
                        type: .string,
                        description: "Explanation of point allocation"
                    )
                ],
                required: ["strengthAndVoiceAnalysis", "scoreAllocations", "verdict"],
                additionalProperties: false
            )
        }
    }
    // MARK: - Debugging Helper
    /// Saves the provided prompt text to the user's `Downloads` folder for debugging purposes.
    private func savePromptToDownloads(content: String, fileName: String) {
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
        let fileURL = downloadsURL.appendingPathComponent(fileName)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            Logger.debug("🪵 Failed to save debug prompt \(fileName): \(error.localizedDescription)")
        }
    }
}
