//
//  JobURLImportService.swift
//  Sprung
//
//  Pure, testable halves of the "import a job posting" flow: the
//  structured-output schema, the OpenAI Responses request construction (a URL
//  variant that web-searches the page, and a text variant for posting text
//  supplied directly, e.g. from the LinkedIn MCP details tool), and the
//  response-text → JobApp parse. NewAppSheetView keeps only the thin streaming
//  drain + UI status (untestable live glue); everything worth a unit test lives here.
//

import Foundation
import SwiftOpenAI

enum JobURLImportService {

    static let systemPrompt = """
    You are a job listing data extractor. When given a job listing URL, use web search to fetch the page and extract structured job information.
    Extract ALL available information from the job posting. For job_description, include the COMPLETE description with all responsibilities, requirements, qualifications, and any other details. Do not summarize or truncate.
    For any field where the information is not provided on the job listing, use "Not specified" as the value.
    """

    /// Structured-output schema for the extracted job fields.
    static var jobSchema: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Extracted job listing information",
            properties: [
                "job_title": JSONSchema(type: .string, description: "The exact job title as shown in the posting"),
                "company": JSONSchema(type: .string, description: "Company name"),
                "location": JSONSchema(type: .string, description: "Job location (city, state/country)"),
                "workplace_type": JSONSchema(type: .string, description: "Remote, Hybrid, Onsite, or Flexible"),
                "employment_type": JSONSchema(type: .string, description: "Full-time, Part-time, Contract, Internship, etc."),
                "seniority_level": JSONSchema(type: .string, description: "Entry, Mid, Senior, Lead, Director, etc. if mentioned"),
                "industries": JSONSchema(type: .string, description: "Relevant industries or sectors"),
                "posted_date": JSONSchema(type: .string, description: "When the job was posted, if available"),
                "salary": JSONSchema(type: .string, description: "Salary range or compensation details if mentioned"),
                "job_description": JSONSchema(type: .string, description: "The COMPLETE job description including all responsibilities, requirements, qualifications, benefits, and any other details. Do not summarize."),
                "apply_link": JSONSchema(type: .string, description: "Direct application URL if different from the source URL")
            ],
            required: ["job_title", "company", "location", "workplace_type", "employment_type", "seniority_level", "industries", "posted_date", "salary", "job_description", "apply_link"],
            additionalProperties: false
        )
    }

    /// System prompt for the text-input variant: the posting text is supplied
    /// directly (e.g. LinkedIn MCP `get_job_details` innerText), so there is
    /// no web-search step.
    static let textSystemPrompt = """
    You are a job listing data extractor. You are given the raw text of a job posting page. Extract structured job information from that text.
    Extract ALL available information from the posting. For job_description, include the COMPLETE description with all responsibilities, requirements, qualifications, and any other details. Do not summarize or truncate.
    For any field where the information is not provided in the posting text, use "Not specified" as the value.
    """

    /// Explicit output ceiling for the text-input extraction: reasoning +
    /// structured output without a cap silently truncates the JSON. Postings
    /// run a few KB of innerText, so this comfortably clears the largest
    /// extracted record while still bounding a runaway response.
    static let textVariantMaxOutputTokens = 8192

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

    /// Build the Responses-API request for extracting a job from `url` using the
    /// user-configured `modelId` (web search + structured output, low reasoning).
    static func buildParameters(url: URL, modelId: String) -> ModelResponseParameter {
        let developerMessage = InputMessage(role: "developer", content: .text(systemPrompt))
        let userInputMessage = InputMessage(
            role: "user",
            content: .text("Extract all job information from: \(url.absoluteString)")
        )
        let inputItems: [InputItem] = [.message(developerMessage), .message(userInputMessage)]
        let webSearchTool = Tool.webSearch(Tool.WebSearchTool(type: .webSearch, userLocation: nil))
        return ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            reasoning: Reasoning(effort: "low"),
            store: true,
            stream: true,
            text: TextConfiguration(format: .jsonSchema(jobSchema, name: "job_listing")),
            toolChoice: .auto,
            tools: [webSearchTool]
        )
    }

    /// Build the Responses-API request for extracting a job from posting text
    /// supplied directly — same output schema and model setting as the URL
    /// variant, but no web-search tool and an explicit output-token cap.
    static func buildTextParameters(postingText: String, modelId: String) -> ModelResponseParameter {
        let developerMessage = InputMessage(role: "developer", content: .text(textSystemPrompt))
        let userInputMessage = InputMessage(
            role: "user",
            content: .text("Extract all job information from this job posting text:\n\n\(postingText)")
        )
        let inputItems: [InputItem] = [.message(developerMessage), .message(userInputMessage)]
        return ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            maxOutputTokens: textVariantMaxOutputTokens,
            reasoning: Reasoning(effort: "low"),
            store: true,
            stream: true,
            text: TextConfiguration(format: .jsonSchema(jobSchema, name: "job_listing"))
        )
    }

    /// Pull the first output-text block out of a completed Responses model result.
    static func extractResponseText(from response: ResponseModel) -> String? {
        for item in response.output {
            if case .message(let message) = item {
                for content in message.content {
                    if case .outputText(let text) = content {
                        return text.text
                    }
                }
            }
        }
        return nil
    }

    /// Parse the model's JSON (tolerating ```json fences) into a JobApp. Returns nil
    /// if the JSON is malformed or missing the essential title/company fields.
    static func parseJob(from jsonString: String, sourceURL: String) -> JobApp? {
        var cleaned = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.error("🚨 [LLM] Failed to parse JSON: \(cleaned.prefix(200))", category: .ai)
            return nil
        }

        let jobApp = JobApp()
        jobApp.postingURL = sourceURL
        jobApp.jobPosition = json["job_title"] as? String ?? ""
        jobApp.companyName = json["company"] as? String ?? ""
        jobApp.jobLocation = json["location"] as? String ?? ""
        jobApp.employmentType = json["employment_type"] as? String ?? ""
        jobApp.seniorityLevel = json["seniority_level"] as? String ?? ""
        jobApp.industries = json["industries"] as? String ?? ""
        jobApp.jobPostingTime = json["posted_date"] as? String ?? ""
        jobApp.jobDescription = json["job_description"] as? String ?? ""

        if let applyLink = json["apply_link"] as? String, !applyLink.isEmpty {
            jobApp.jobApplyLink = applyLink
        } else {
            jobApp.jobApplyLink = sourceURL
        }

        // Extract salary to dedicated field
        if let salary = json["salary"] as? String, !salary.isEmpty, salary != "Not specified" {
            jobApp.salary = salary
        }

        // Add workplace type to employment type if present
        if let workplaceType = json["workplace_type"] as? String, !workplaceType.isEmpty {
            if jobApp.employmentType.isEmpty {
                jobApp.employmentType = workplaceType
            } else {
                jobApp.employmentType += " (\(workplaceType))"
            }
        }

        jobApp.status = .new
        jobApp.identifiedDate = Date()
        jobApp.source = "LLM Import"

        // Validate we got essential data
        guard !jobApp.jobPosition.isEmpty && !jobApp.companyName.isEmpty else {
            Logger.warning("⚠️ [LLM] Missing essential data (title or company)", category: .ai)
            return nil
        }

        return jobApp
    }
}
