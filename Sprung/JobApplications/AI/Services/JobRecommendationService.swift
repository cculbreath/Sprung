//
//  JobRecommendationService.swift
//  Sprung
//
//  Created by Christopher Culbreath on 6/4/25.
//
import Foundation
/// Service for job recommendation using the unified LLM architecture
/// Replaces JobRecommendationProvider with cleaner LLMService integration
@MainActor
class JobRecommendationService {

    // MARK: - Dependencies
    private let llm: LLMFacade
    private var resumeContextCache: [UUID: String] = [:]

    // MARK: - Configuration
    private let systemPrompt = """
    You are an expert career advisor specializing in job application prioritization. Your task is to analyze a list of job applications and recommend the one that best matches the candidate's qualifications and career goals. You will be provided with job descriptions, the candidate's resume, and additional background information. Choose the job that offers the best match in terms of skills, experience, and potential career growth.
    IMPORTANT: Your response must be a valid JSON object conforming to the JSON schema provided. The recommendedJobId field must contain the exact UUID string from the id field of the chosen job in the job listings JSON array. Do not modify the UUID format in any way.
    IMPORTANT: Output ONLY the JSON object with the fields "recommendedJobId" and "reason". Do not include any additional commentary, explanation, or text outside the JSON.
    """
    private let maxResumeContextBytes = 120_000

    init(llmFacade: LLMFacade) {
        self.llm = llmFacade
    }

    // MARK: - Public Interface
    /// Fetch job recommendation using LLMService
    /// - Parameters:
    ///   - jobApps: Array of job applications to consider
    ///   - modelId: The model to use for recommendation
    ///   - includeResumeBackground: Whether to include resume background sources
    ///   - includeCoverLetterBackground: Whether to include cover letter background facts
    /// - Returns: Tuple containing recommended job ID and reason
    func fetchRecommendation(
        jobApps: [JobApp],
        modelId: String,
        includeResumeBackground: Bool = true,
        includeCoverLetterBackground: Bool = false
    ) async throws -> (UUID, String) {

        // Find the most recently edited resume from job apps with priority status
        let resume = findMostRecentResume(from: jobApps)

        // If no resume found, check if we have background information to proceed
        if resume == nil {
            if !includeResumeBackground && !includeCoverLetterBackground {
                throw JobRecommendationError.noResumeOrBackgroundInfo
            }
            // Check if we actually have background content available
            let hasBackgroundContent = (includeResumeBackground && hasResumeBackgroundContent(from: jobApps)) ||
                                     (includeCoverLetterBackground && hasCoverLetterBackgroundContent(from: jobApps))
            if !hasBackgroundContent {
                throw JobRecommendationError.noResumeOrBackgroundInfo
            }
        }

        let newJobApps = jobApps.filter { $0.status == .new }
        guard !newJobApps.isEmpty else {
            throw JobRecommendationError.noNewJobApplications
        }

        // Note: Capability gating to be centralized in facade in a later slice

        // Build the recommendation prompt
        let prompt = buildPrompt(
            newJobApps: newJobApps,
            resume: resume,
            includeResumeBackground: includeResumeBackground,
            includeCoverLetterBackground: includeCoverLetterBackground
        )

        // Debug logging if enabled
        if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
            saveDebugPrompt(content: prompt, fileName: "jobRecommendationPrompt.txt")
        }

        Logger.debug("🎯 Requesting job recommendation with \(newJobApps.count) new jobs")

        // Execute structured request
        let recommendation: JobRecommendation = try await llm.executeStructured(
            prompt: "\(systemPrompt)\n\n\(prompt)",
            modelId: modelId,
            as: JobRecommendation.self,
            temperature: nil
        )

        // Validate response
        guard recommendation.validate() else {
            throw JobRecommendationError.invalidResponse("Failed validation")
        }

        guard let uuid = UUID(uuidString: recommendation.recommendedJobId) else {
            throw JobRecommendationError.invalidUUID(recommendation.recommendedJobId)
        }

        Logger.debug("✅ Job recommendation successful: \(recommendation.recommendedJobId)")
        return (uuid, recommendation.reason)
    }

    // MARK: - Private Helpers
    /// Find the most recently edited resume based on job app status priority
    private func findMostRecentResume(from jobApps: [JobApp]) -> Resume? {
        // Status priority: "interview pending" > "submitted" > "rejected"
        let statusPriority: [Statuses] = [.interview, .submitted, .rejected]

        var candidateResumes: [(Resume, Date, Int)] = []

        for jobApp in jobApps {
            for resume in jobApp.resumes {
                let lastModified = resume.dateCreated
                let priorityScore = statusPriority.firstIndex(of: jobApp.status) ?? Int.max
                candidateResumes.append((resume, lastModified, priorityScore))
            }
        }

        // Sort by priority first, then by most recent modification date
        candidateResumes.sort { lhs, rhs in
            if lhs.2 != rhs.2 {
                return lhs.2 < rhs.2  // Better priority (lower score)
            }
            return lhs.1 > rhs.1  // More recent date
        }

        return candidateResumes.first?.0
    }

    /// Build the recommendation prompt with job listings and resume data
    private func buildPrompt(
        newJobApps: [JobApp],
        resume: Resume?,
        includeResumeBackground: Bool,
        includeCoverLetterBackground: Bool
    ) -> String {
        let resumeText = resume.flatMap { resumeContextString(for: $0) } ?? ""

        // Build background documentation
        let backgroundDocs = includeResumeBackground ? buildBackgroundDocs(from: resume) : ""
        let coverLetterBackgroundDocs = includeCoverLetterBackground ? buildCoverLetterBackgroundDocs(from: newJobApps) : ""

        // Create JSON array of job listings
        var jobsArray: [[String: Any]] = []
        for app in newJobApps {
            let jobDict: [String: Any] = [
                "id": app.id.uuidString,
                "position": app.jobPosition,
                "company": app.companyName,
                "location": app.jobLocation,
                "description": app.jobDescription
            ]
            jobsArray.append(jobDict)
        }

        // Convert to JSON string
        let jsonString: String
        if let jsonData = try? JSONSerialization.data(withJSONObject: jobsArray, options: [.prettyPrinted]) {
            jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        } else {
            jsonString = "[]"
        }

        let prompt = """
        TASK:
        Analyze the candidate's information and the list of new job applications. Recommend the ONE job that is the best match for the candidate's qualifications and career goals.
        \(resumeText.isEmpty ? "" : """
        CANDIDATE'S RESUME:
        \(resumeText)
        """)
        \(backgroundDocs.isEmpty ? "" : """
        BACKGROUND INFORMATION:
        \(backgroundDocs)
        """)
        \(coverLetterBackgroundDocs.isEmpty ? "" : """
        COVER LETTER BACKGROUND FACTS:
        \(coverLetterBackgroundDocs)
        """)
        JOB LISTINGS (JSON FORMAT):
        \(jsonString)
        RESPONSE REQUIREMENTS:
        - You MUST respond with a valid JSON object containing exactly these fields:
          "recommendedJobId": The exact UUID string from the 'id' field of the best matching job
          "reason": A brief explanation of why this job is the best match
        - The recommendedJobId MUST be copied exactly from the job listing, character-for-character
        - Do not include any text, comments, or explanations outside the JSON object
        - Your entire response must be a valid JSON structure
        Example response format:
        {
          "recommendedJobId": "00000000-0000-0000-0000-000000000000",
          "reason": "This job aligns with the candidate's experience in..."
        }
        """

        return prompt
    }

    private func resumeContextString(for resume: Resume) -> String {
        if let cached = resumeContextCache[resume.id] {
            return cached
        }
        if !resume.textResume.isEmpty {
            resumeContextCache[resume.id] = resume.textResume
            return resume.textResume
        }
        guard let context = try? ResumeTemplateDataBuilder.buildContext(from: resume),
              let data = try? JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            resumeContextCache[resume.id] = ""
            return ""
        }
        let byteCount = string.utf8.count
        if byteCount > maxResumeContextBytes {
            Logger.warning("JobRecommendationService: resume context for \(resume.id) is \(byteCount) bytes; truncating to \(maxResumeContextBytes).")
            let truncated = truncateContext(string, maxBytes: maxResumeContextBytes)
            let annotated = truncated + "\n\n/* truncated resume context to fit job recommendation prompt */"
            resumeContextCache[resume.id] = annotated
            return annotated
        }
        resumeContextCache[resume.id] = string
        return string
    }
    private func truncateContext(_ string: String, maxBytes: Int) -> String {
        var consumedBytes = 0
        var index = string.startIndex
        while index < string.endIndex {
            let character = string[index]
            let characterBytes = character.utf8.count
            if consumedBytes + characterBytes > maxBytes {
                break
            }
            consumedBytes += characterBytes
            index = string.index(after: index)
        }
        var truncated = String(string[string.startIndex..<index])
        if truncated.last?.isWhitespace == false {
            truncated.append(" ")
        }
        truncated.append(contentsOf: "...")
        return truncated
    }
    /// Build background documentation from resume sources
    private func buildBackgroundDocs(from resume: Resume?) -> String {
        guard let resume = resume else { return "" }
        let enabledSources = resume.enabledSources
        if enabledSources.isEmpty {
            return ""
        } else {
            return enabledSources.map { $0.name + ":\n" + $0.content + "\n\n" }.joined()
        }
    }

    /// Build cover letter background facts from job applications
    private func buildCoverLetterBackgroundDocs(from jobApps: [JobApp]) -> String {
        var backgroundFacts: [String] = []

        for jobApp in jobApps {
            for coverLetter in jobApp.coverLetters {
                let facts = coverLetter.backgroundItemsString
                if !facts.isEmpty {
                    backgroundFacts.append(facts)
                }
            }
        }

        return backgroundFacts.joined(separator: "\n\n")
    }

    /// Check if job apps have resume background content
    private func hasResumeBackgroundContent(from jobApps: [JobApp]) -> Bool {
        for jobApp in jobApps {
            for resume in jobApp.resumes where !resume.enabledSources.isEmpty {
                return true
            }
        }
        return false
    }

    /// Check if job apps have cover letter background content
    private func hasCoverLetterBackgroundContent(from jobApps: [JobApp]) -> Bool {
        for jobApp in jobApps {
            for coverLetter in jobApp.coverLetters where !coverLetter.backgroundItemsString.isEmpty {
                return true
            }
        }
        return false
    }

    /// Save debug prompt to file if debug mode is enabled
    private func saveDebugPrompt(content: String, fileName: String) {
        let fileManager = FileManager.default
        guard let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.warning("⚠️ Unable to locate Application Support directory for debug prompt.")
            return
        }
        let debugDirectory = supportDirectory.appendingPathComponent("Sprung/Debug", isDirectory: true)
        do {
            try fileManager.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.warning("⚠️ Failed to create debug directory: \(error.localizedDescription)")
            return
        }
        let fileURL = debugDirectory.appendingPathComponent(fileName)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            Logger.debug("💾 Saved debug file to Application Support: \(fileName)")
        } catch {
            Logger.warning("⚠️ Failed to save debug file \(fileName): \(error.localizedDescription)")
        }
    }
}
// MARK: - Supporting Types
/// Errors specific to job recommendation service
enum JobRecommendationError: LocalizedError {
    case noResumeAvailable
    case noNewJobApplications
    case noResumeOrBackgroundInfo
    case invalidResponse(String)
    case invalidUUID(String)

    var errorDescription: String? {
        switch self {
        case .noResumeAvailable:
            return "No resume available"
        case .noNewJobApplications:
            return "No new job applications available"
        case .noResumeOrBackgroundInfo:
            return "Best job cannot be determined without either a resume from post-submission job applications or enabling background information"
        case .invalidResponse(let details):
            return "Invalid recommendation format: \(details)"
        case .invalidUUID(let uuid):
            return "Invalid UUID format in response: \(uuid)"
        }
    }
}
/// Job recommendation response structure (reusing existing type from JobRecommendationProvider)
struct JobRecommendation: Codable {
    let recommendedJobId: String
    let reason: String

    /// Validate that the recommendedJobId is a valid UUID
    func validate() -> Bool {
        return UUID(uuidString: recommendedJobId) != nil
    }
}
