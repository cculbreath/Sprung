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

@Observable class CoverLetterQuery {
    // MARK: - Properties
    
    /// Set this to `true` if you want to save a debug file containing the prompt text.
    var saveDebugPrompt: Bool = false
    
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
    
    var resumeText: String {
        if !resume.textRes.isEmpty {
            return resume.textRes
        }
        Logger.debug("⚠️BLANK TEXT RES⚠️")
        guard let context = try? ResumeTemplateDataBuilder.buildContext(from: resume),
              let data = try? JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }

        let byteCount = string.utf8.count
        guard byteCount > Self.maxResumeContextBytes else {
            return string
        }

        Logger.warning("CoverLetterQuery: resume context is \(byteCount) bytes; truncating to \(Self.maxResumeContextBytes) bytes to avoid prompt overflow.")
        let truncated = truncateContext(string, maxBytes: Self.maxResumeContextBytes)
        return truncated + "\n\n/* truncated resume context to fit cover letter prompt */"
    }
    
    var backgroundDocs: String {
        let bgrefs = resume.enabledSources
        if bgrefs.isEmpty {
            return ""
        } else {
            return bgrefs.map { $0.name + ":\n" + $0.content + "\n\n" }.joined()
        }
    }
    
    var writingSamples: String {
        return coverLetter.writingSamplesString
    }

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
        saveDebugPrompt: Bool = false
    ) {
        self.coverLetter = coverLetter
        self.resume = resume
        self.jobApp = jobApp
        self.saveDebugPrompt = saveDebugPrompt
        self.exportCoordinator = exportCoordinator
        
        // Create a complete applicant profile with default values
        let profile = ApplicantProfile()
        applicant = Applicant(
            name: profile.name,
            address: profile.address,
            city: profile.city,
            state: profile.state,
            zip: profile.zip,
            websites: profile.websites,
            email: profile.email,
            phone: profile.phone
        )
    }
    
    // MARK: - System Prompts
    
    /// System prompt for cover letter generation
    func systemPrompt(for modelId: String) -> String {
        var systemPrompt = CoverLetterPrompts.systemMessage.textContent
        
        // Model-specific formatting instructions
        if modelId.lowercased().contains("gemini") {
            systemPrompt += " Do not format your response as JSON. Return the cover letter text directly without any JSON wrapping or structure."
        } else if modelId.lowercased().contains("claude") {
            systemPrompt += "\n\nIMPORTANT: Return ONLY the plain text body of the cover letter. Do NOT include JSON formatting, do NOT include 'Dear Hiring Manager' or any salutation, do NOT include any closing or signature. Start directly with the first paragraph of the letter body and end with the last paragraph. No JSON, no formatting, just the plain text paragraphs."
        }
        
        return systemPrompt
    }
    
    // MARK: - Cover Letter Prompts
    
    /// Generate prompt for cover letter generation
    @MainActor
    func generationPrompt(includeResumeRefs: Bool = true) async -> String {
        // Ensure resume text is fresh
        try? await exportCoordinator.ensureFreshRenderedText(for: resume)
        
        let prompt = """
        ================================================================================
        COVER LETTER GENERATION REQUEST
        ================================================================================
        
        GOAL:
        Create a compelling cover letter for \(applicant.name) to secure an interview for the following position:
        
        JOB LISTING:
        \(jobListing)
        
        RESUME CONTEXT:
        \(resumeText)
        
        \(includeResumeRefs ? """
        BACKGROUND DOCUMENTS:
        \(backgroundDocs)
        """ : "")
        
        WRITING STYLE REFERENCE:
        \(writingSamples)
        
        INSTRUCTIONS:
        - Write a personalized cover letter that aligns with the job requirements
        - Reflect the candidate's authentic voice based on the writing samples
        - Highlight relevant achievements from the resume
        - Use keywords from the job listing appropriately
        - Keep the tone professional yet engaging
        - Focus on value proposition and fit for the role
        
        Return only the body text of the cover letter without salutation or closing.
        ================================================================================
        """
        
        if saveDebugPrompt {
            savePromptToDownloads(content: prompt, fileName: "coverLetterGenerationPrompt.txt")
        }
        
        return prompt
    }
    
    /// Generate prompt for cover letter revision
    @MainActor
    func revisionPrompt(
        feedback: String,
        editorPrompt: CoverLetterPrompts.EditorPrompts = .improve
    ) async -> String {
        try? await exportCoordinator.ensureFreshRenderedText(for: resume)
        
        let prompt: String
        if editorPrompt == .custom {
            prompt = """
            Upon reading your latest draft, \(applicant.name) has provided the following feedback:

                \(feedback)

            Please prepare a revised draft that improves upon the original while incorporating this feedback. 
            Your response should only include the plain full text of the revised letter draft without any 
            markdown formatting or additional explanations or reasoning.

            Current draft:
            \(coverLetter.content)
            """
        } else {
            prompt = CoverLetterPrompts.generate(
                coverLetter: coverLetter,
                resume: resume,
                mode: .rewrite,
                customFeedbackString: feedback
            )
        }
        
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
        \(writingSamples)
        
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
        } catch {}
    }
}
