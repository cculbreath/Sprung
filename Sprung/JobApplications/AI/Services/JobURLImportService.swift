//
//  JobURLImportService.swift
//  Sprung
//
//  Pure, testable halves of the "import a job posting" flow: the
//  jobImportModelId resolution (throws instead of substituting a default) and
//  the extracted-fields → JobApp mapping. The live extraction runs through
//  JobImportLoop (Anthropic server-side web_fetch + the strict submit_job
//  tool); everything worth a unit test lives here.
//

import Foundation

/// The fields the `submit_job` tool returns — camelCase keys we control, decoded
/// straight from the tool-call input JSON.
struct ImportedJobFields: Codable {
    let jobTitle: String
    let company: String
    let location: String
    let workplaceType: String
    let employmentType: String
    let seniorityLevel: String
    let industries: String
    let postedDate: String
    let salary: String
    let jobDescription: String
    let applyLink: String
}

enum JobURLImportService {

    /// Values the extractor emits for an absent field; never populate a stored
    /// field with them.
    private static let absentFieldMarker = "Not specified"

    /// Resolve the user-configured job-import model id, throwing (never
    /// substituting a default) when it isn't configured.
    static func requireJobImportModelId(
        operationName: String,
        defaults: UserDefaults = .standard
    ) throws -> String {
        guard let modelId = defaults.string(forKey: "jobImportModelId"), !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "jobImportModelId",
                operationName: operationName
            )
        }
        return modelId
    }

    /// Map the extracted fields into a JobApp. Returns nil if the essential
    /// title/company are missing (so the agent is asked to re-extract).
    static func makeJobApp(from fields: ImportedJobFields, sourceURL: String) -> JobApp? {
        let jobApp = JobApp()
        jobApp.postingURL = sourceURL
        jobApp.jobPosition = fields.jobTitle
        jobApp.companyName = fields.company
        jobApp.jobLocation = fields.location
        jobApp.employmentType = fields.employmentType
        jobApp.seniorityLevel = fields.seniorityLevel
        jobApp.industries = fields.industries
        jobApp.jobPostingTime = fields.postedDate
        jobApp.jobDescription = fields.jobDescription

        let applyLink = normalized(fields.applyLink)
        jobApp.jobApplyLink = applyLink.isEmpty ? sourceURL : applyLink

        let salary = normalized(fields.salary)
        if !salary.isEmpty {
            jobApp.salary = salary
        }

        // Fold workplace type into employment type when present.
        let workplaceType = normalized(fields.workplaceType)
        if !workplaceType.isEmpty {
            if jobApp.employmentType.isEmpty {
                jobApp.employmentType = workplaceType
            } else {
                jobApp.employmentType += " (\(workplaceType))"
            }
        }

        jobApp.status = .new
        jobApp.identifiedDate = Date()
        jobApp.source = "LLM Import"

        guard !jobApp.jobPosition.isEmpty && !jobApp.companyName.isEmpty else {
            Logger.warning("⚠️ [LLM] Missing essential data (title or company)", category: .ai)
            return nil
        }
        return jobApp
    }

    /// Empty string for a blank value or the extractor's "Not specified" filler.
    private static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == absentFieldMarker ? "" : trimmed
    }
}
