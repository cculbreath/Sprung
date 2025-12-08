//
//  CompleteAnalysisTool.swift
//  Sprung
//
//  Tool for submitting comprehensive git repository analysis results.
//  Extracted from FileSystemTools.swift for better organization.
//

import Foundation

// MARK: - Complete Analysis Tool

struct CompleteAnalysisTool: AgentTool {
    static let name = "complete_analysis"
    static let description = """
        Call this tool when you have finished analyzing the repository and are ready to submit your findings.
        Provide a COMPREHENSIVE, DETAILED assessment of the developer's skills based on the code you examined.
        IMPORTANT: This analysis will be used to generate resume and cover letter content. Be thorough and specific.
        Each field should contain substantial detail - avoid brief, surface-level descriptions.
        Generate resume-ready bullets and cover letter phrases where indicated.
        """

    // swiftlint:disable function_body_length
    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "repository_summary": [
                "type": "object",
                "description": "High-level metadata about the repository analyzed",
                "properties": [
                    "name": ["type": "string", "description": "Repository/project name"],
                    "description": ["type": "string", "description": "Brief description of what the project does"],
                    "primary_domain": ["type": "string", "description": "Problem domain (fintech, devops, web app, etc.)"],
                    "project_type": ["type": "string", "description": "Type: library, application, CLI, API, framework, etc."],
                    "maturity_level": ["type": "string", "description": "Maturity: prototype, production, maintained OSS, etc."]
                ],
                "required": ["name", "description", "primary_domain", "project_type"]
            ],
            "technical_skills": [
                "type": "array",
                "description": "All technical skills identified with proficiency assessment and resume-ready content. Include 10-20 skills for substantial projects.",
                "items": [
                    "type": "object",
                    "properties": [
                        "skill_name": ["type": "string", "description": "Name of the skill/technology"],
                        "category": ["type": "string", "enum": ["language", "framework", "tool", "platform", "database", "methodology"], "description": "Skill category"],
                        "proficiency_level": ["type": "string", "enum": ["expert", "proficient", "competent", "familiar"], "description": "Proficiency level based on evidence"],
                        "evidence": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "type": ["type": "string", "description": "Evidence type: code_pattern, usage_frequency, complexity_handled, documentation"],
                                    "description": ["type": "string", "description": "2-4 sentences explaining the evidence"],
                                    "file_references": ["type": "array", "items": ["type": "string"], "description": "File paths with optional line numbers"]
                                ]
                            ],
                            "description": "Concrete evidence supporting this proficiency assessment"
                        ],
                        "resume_bullets": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "1-3 achievement-oriented statements suitable for resume. Quantify where possible."
                        ]
                    ],
                    "required": ["skill_name", "category", "proficiency_level", "evidence", "resume_bullets"]
                ]
            ],
            "ai_collaboration_profile": [
                "type": "object",
                "description": "Detailed assessment of AI-assisted development practices. Include even if no AI usage detected.",
                "properties": [
                    "detected_ai_usage": ["type": "boolean", "description": "Whether AI tool usage was detected"],
                    "usage_confidence": ["type": "string", "enum": ["high", "medium", "low", "none"], "description": "Confidence in the detection"],
                    "explicit_indicators": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "type": ["type": "string", "description": "Indicator type: config_file, commit_message, comment, prompt_file"],
                                "location": ["type": "string", "description": "File path or reference"],
                                "description": ["type": "string", "description": "What was found"]
                            ]
                        ],
                        "description": "Explicit indicators found (config files, commit messages, comments)"
                    ],
                    "implicit_indicators": ["type": "array", "items": ["type": "string"], "description": "Implicit signals suggesting AI usage"],
                    "collaboration_quality_rating": [
                        "type": "string",
                        "enum": ["ai_augmented_expert", "effective_collaborator", "developing_user", "over_reliant", "no_detected_usage"],
                        "description": "Overall rating of AI collaboration quality"
                    ],
                    "quality_evidence": [
                        "type": "object",
                        "properties": [
                            "strengths": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "indicator": ["type": "string"],
                                        "evidence": ["type": "string"],
                                        "file_references": ["type": "array", "items": ["type": "string"]]
                                    ]
                                ],
                                "description": "Positive indicators of effective AI collaboration"
                            ],
                            "concerns": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "indicator": ["type": "string"],
                                        "evidence": ["type": "string"],
                                        "file_references": ["type": "array", "items": ["type": "string"]],
                                        "severity": ["type": "string", "enum": ["minor", "moderate", "significant"]]
                                    ]
                                ],
                                "description": "Quality concerns or red flags (empty array if none)"
                            ]
                        ]
                    ],
                    "resume_positioning": [
                        "type": "object",
                        "properties": [
                            "include_as_skill": ["type": "boolean", "description": "Whether to include AI collaboration as a skill on resume"],
                            "framing_recommendation": ["type": "string", "description": "How to frame AI skills if included"],
                            "suggested_bullets": ["type": "array", "items": ["type": "string"], "description": "Resume bullets if appropriate"]
                        ]
                    ]
                ],
                "required": ["detected_ai_usage", "usage_confidence", "collaboration_quality_rating"]
            ],
            "architectural_competencies": [
                "type": "array",
                "description": "Higher-level architectural and design competencies demonstrated",
                "items": [
                    "type": "object",
                    "properties": [
                        "competency": ["type": "string", "description": "e.g., 'Microservices Design', 'API Architecture', 'Event-Driven Systems'"],
                        "evidence_summary": ["type": "string", "description": "Full paragraph explaining how this competency is demonstrated"],
                        "proficiency_level": ["type": "string", "enum": ["expert", "proficient", "competent", "familiar"]],
                        "resume_bullets": ["type": "array", "items": ["type": "string"], "description": "Resume-ready achievement statements"]
                    ],
                    "required": ["competency", "evidence_summary", "proficiency_level"]
                ]
            ],
            "professional_attributes": [
                "type": "array",
                "description": "Soft skills and professional qualities inferred from the codebase",
                "items": [
                    "type": "object",
                    "properties": [
                        "attribute": ["type": "string", "description": "e.g., 'Technical Communication', 'Attention to Detail', 'Problem-Solving'"],
                        "strength_level": ["type": "string", "enum": ["exceptional", "strong", "evident", "emerging"]],
                        "evidence": ["type": "string", "description": "How this attribute is demonstrated in the code"],
                        "cover_letter_phrases": ["type": "array", "items": ["type": "string"], "description": "Phrases suitable for cover letter narrative"]
                    ],
                    "required": ["attribute", "strength_level", "evidence"]
                ]
            ],
            "quantitative_metrics": [
                "type": "object",
                "description": "Quantitative measurements from the codebase",
                "properties": [
                    "languages_breakdown": ["type": "object", "description": "Language name to percentage mapping"],
                    "estimated_lines_of_code": ["type": "integer", "description": "Approximate total LOC"],
                    "files_analyzed": ["type": "integer", "description": "Number of significant files examined"],
                    "test_coverage_assessment": ["type": "string", "description": "Qualitative assessment of test coverage"],
                    "documentation_coverage": ["type": "string", "description": "Qualitative assessment of documentation"]
                ]
            ],
            "notable_achievements": [
                "type": "array",
                "description": "Specific accomplishments that stand out. Include 5-15 for substantial projects.",
                "items": [
                    "type": "object",
                    "properties": [
                        "achievement": ["type": "string", "description": "What was accomplished"],
                        "impact": ["type": "string", "description": "Why it matters / business impact"],
                        "technologies_involved": ["type": "array", "items": ["type": "string"]],
                        "resume_bullet": ["type": "string", "description": "Achievement-oriented resume statement, quantified where possible"]
                    ],
                    "required": ["achievement", "impact", "resume_bullet"]
                ]
            ],
            "keyword_cloud": [
                "type": "object",
                "description": "Keywords for ATS optimization and skill tagging",
                "properties": [
                    "primary": ["type": "array", "items": ["type": "string"], "description": "Top skills for ATS optimization"],
                    "secondary": ["type": "array", "items": ["type": "string"], "description": "Supporting technologies"],
                    "soft_skills": ["type": "array", "items": ["type": "string"], "description": "Inferred professional qualities"],
                    "modern_practices": ["type": "array", "items": ["type": "string"], "description": "Modern workflow skills (AI collaboration, etc.)"]
                ]
            ],
            "evidence_files": [
                "type": "array",
                "description": "All significant files that were examined to support this analysis",
                "items": ["type": "string"]
            ]
        ],
        "required": ["repository_summary", "technical_skills", "ai_collaboration_profile", "notable_achievements", "keyword_cloud", "evidence_files"],
        "additionalProperties": false
    ]
    // swiftlint:enable function_body_length

    // MARK: - Nested Types for Decoding

    struct RepositorySummary: Codable {
        let name: String
        let description: String
        let primaryDomain: String
        let projectType: String
        let maturityLevel: String?

        enum CodingKeys: String, CodingKey {
            case name, description
            case primaryDomain = "primary_domain"
            case projectType = "project_type"
            case maturityLevel = "maturity_level"
        }
    }

    struct SkillEvidence: Codable {
        let type: String?
        let description: String?
        let fileReferences: [String]?

        enum CodingKeys: String, CodingKey {
            case type, description
            case fileReferences = "file_references"
        }
    }

    struct TechnicalSkill: Codable {
        let skillName: String
        let category: String
        let proficiencyLevel: String
        let evidence: [SkillEvidence]?
        let resumeBullets: [String]?

        enum CodingKeys: String, CodingKey {
            case skillName = "skill_name"
            case category
            case proficiencyLevel = "proficiency_level"
            case evidence
            case resumeBullets = "resume_bullets"
        }
    }

    struct ExplicitIndicator: Codable {
        let type: String?
        let location: String?
        let description: String?
    }

    struct QualityStrength: Codable {
        let indicator: String?
        let evidence: String?
        let fileReferences: [String]?

        enum CodingKeys: String, CodingKey {
            case indicator, evidence
            case fileReferences = "file_references"
        }
    }

    struct QualityConcern: Codable {
        let indicator: String?
        let evidence: String?
        let fileReferences: [String]?
        let severity: String?

        enum CodingKeys: String, CodingKey {
            case indicator, evidence, severity
            case fileReferences = "file_references"
        }
    }

    struct QualityEvidence: Codable {
        let strengths: [QualityStrength]?
        let concerns: [QualityConcern]?
    }

    struct ResumePositioning: Codable {
        let includeAsSkill: Bool?
        let framingRecommendation: String?
        let suggestedBullets: [String]?

        enum CodingKeys: String, CodingKey {
            case includeAsSkill = "include_as_skill"
            case framingRecommendation = "framing_recommendation"
            case suggestedBullets = "suggested_bullets"
        }
    }

    struct AICollaborationProfile: Codable {
        let detectedAIUsage: Bool
        let usageConfidence: String
        let explicitIndicators: [ExplicitIndicator]?
        let implicitIndicators: [String]?
        let collaborationQualityRating: String
        let qualityEvidence: QualityEvidence?
        let resumePositioning: ResumePositioning?

        enum CodingKeys: String, CodingKey {
            case detectedAIUsage = "detected_ai_usage"
            case usageConfidence = "usage_confidence"
            case explicitIndicators = "explicit_indicators"
            case implicitIndicators = "implicit_indicators"
            case collaborationQualityRating = "collaboration_quality_rating"
            case qualityEvidence = "quality_evidence"
            case resumePositioning = "resume_positioning"
        }
    }

    struct ArchitecturalCompetency: Codable {
        let competency: String
        let evidenceSummary: String
        let proficiencyLevel: String
        let resumeBullets: [String]?

        enum CodingKeys: String, CodingKey {
            case competency
            case evidenceSummary = "evidence_summary"
            case proficiencyLevel = "proficiency_level"
            case resumeBullets = "resume_bullets"
        }
    }

    struct ProfessionalAttribute: Codable {
        let attribute: String
        let strengthLevel: String
        let evidence: String
        let coverLetterPhrases: [String]?

        enum CodingKeys: String, CodingKey {
            case attribute
            case strengthLevel = "strength_level"
            case evidence
            case coverLetterPhrases = "cover_letter_phrases"
        }
    }

    struct QuantitativeMetrics: Codable {
        let languagesBreakdown: [String: Double]?
        let estimatedLinesOfCode: Int?
        let filesAnalyzed: Int?
        let testCoverageAssessment: String?
        let documentationCoverage: String?

        enum CodingKeys: String, CodingKey {
            case languagesBreakdown = "languages_breakdown"
            case estimatedLinesOfCode = "estimated_lines_of_code"
            case filesAnalyzed = "files_analyzed"
            case testCoverageAssessment = "test_coverage_assessment"
            case documentationCoverage = "documentation_coverage"
        }
    }

    struct NotableAchievement: Codable {
        let achievement: String
        let impact: String
        let technologiesInvolved: [String]?
        let resumeBullet: String

        enum CodingKeys: String, CodingKey {
            case achievement, impact
            case technologiesInvolved = "technologies_involved"
            case resumeBullet = "resume_bullet"
        }
    }

    struct KeywordCloud: Codable {
        let primary: [String]?
        let secondary: [String]?
        let softSkills: [String]?
        let modernPractices: [String]?

        enum CodingKeys: String, CodingKey {
            case primary, secondary
            case softSkills = "soft_skills"
            case modernPractices = "modern_practices"
        }
    }

    struct Parameters: Codable {
        let repositorySummary: RepositorySummary
        let technicalSkills: [TechnicalSkill]
        let aiCollaborationProfile: AICollaborationProfile
        let architecturalCompetencies: [ArchitecturalCompetency]?
        let professionalAttributes: [ProfessionalAttribute]?
        let quantitativeMetrics: QuantitativeMetrics?
        let notableAchievements: [NotableAchievement]
        let keywordCloud: KeywordCloud
        let evidenceFiles: [String]

        enum CodingKeys: String, CodingKey {
            case repositorySummary = "repository_summary"
            case technicalSkills = "technical_skills"
            case aiCollaborationProfile = "ai_collaboration_profile"
            case architecturalCompetencies = "architectural_competencies"
            case professionalAttributes = "professional_attributes"
            case quantitativeMetrics = "quantitative_metrics"
            case notableAchievements = "notable_achievements"
            case keywordCloud = "keyword_cloud"
            case evidenceFiles = "evidence_files"
        }
    }
}
