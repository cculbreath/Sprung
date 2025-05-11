//
//  ResumeReviewType.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/11/25.
//

import Foundation

/// Types of resume review operations available
enum ResumeReviewType: String, CaseIterable, Identifiable {
    case suggestChanges = "Suggest Resume Fields to Change"
    case assessQuality = "Assess Overall Resume Quality"
    case assessFit = "Assess Fit for Job Position"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    /// Returns the prompt template for this review type
    func promptTemplate() -> String {
        switch self {
        case .assessQuality:
            return """
            I am applying for this job opening: 
            {jobPosition}, {companyName}. 
            Job Description:
            {jobDescription}
            ----------------------
            Here is a draft of my current resume:
            {resumeText}
            
            {includeImage}
            Please assess the overall quality of my resume and its applicability to the current job opening. Please share three of its strengths along with three ways that it can be improved.
            """
            
        case .assessFit:
            return """
            I am applying for this job opening: 
            {jobPosition}, {companyName}. 
            Job Description:
            {jobDescription}
            
            Here is a draft of my current resume:
            {resumeText}
            
            {includeImage}
            Do you think I'm a good fit for this position? What are the biggest gaps in my experience, as evident on my resume, relative to the requirements of the position. Do you think that it is worthwhile for me to apply? Based on my resume alone, how strong do you think my application is?
            """
            
        case .suggestChanges:
            return """
            I am applying for this job opening: 
            {jobPosition}, {companyName}. 
            Job Description:
            {jobDescription}
            
            Here is a draft of my current resume:
            {resumeText}
            
            Here is some background information on me and my experience:
            {backgroundDocs}
            
            Can you identify any job titles, skill headings, or specific job details that could particularly benefit from revision? Please specify which specific elements of my resume that I should consider for revision.
            """
            
        case .custom:
            // Custom prompt will be built using the user's input
            return ""
        }
    }
}

/// Options to include in a custom resume review
struct CustomReviewOptions: Equatable {
    var includeJobListing: Bool = true
    var includeResumeText: Bool = true
    var includeResumeImage: Bool = true
    var customPrompt: String = ""
}