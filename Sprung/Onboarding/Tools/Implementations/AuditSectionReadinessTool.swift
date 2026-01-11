//
//  AuditSectionReadinessTool.swift
//  Sprung
//
//  Pre-validation tool that checks if KCs and skills exist for each enabled section
//  before launching the ExperienceDefaults agent. Returns actionable gaps.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

struct AuditSectionReadinessTool: InterviewTool {
    private weak var coordinator: OnboardingInterviewCoordinator?

    var name: String { OnboardingToolName.auditSectionReadiness.rawValue }

    var description: String {
        """
        Audits data readiness for each enabled resume section before generating experience defaults.
        Returns per-section status (ready, incomplete, missing) with specific gaps.

        Call this BEFORE generate_experience_defaults to identify missing data that needs
        to be collected from the user or resolved (e.g., publications enabled but no publication KCs).

        Returns a JSON object with:
        - sections: Array of section audits with status and gaps
        - summary: Overall readiness assessment
        - actionRequired: Boolean indicating if user input is needed
        """
    }

    var parameters: JSONSchema {
        JSONSchema(
            type: .object,
            description: "No parameters required - audits all enabled sections",
            properties: [:],
            required: []
        )
    }

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }

        // Gather data - getEnabledSections is async, others need MainActor
        let enabledSections = await coordinator.state.getEnabledSections()
        let (knowledgeCards, skills, timelineEntries) = await MainActor.run {
            (
                coordinator.getKnowledgeCardStore().onboardingCards,
                coordinator.skillStore.skills,
                coordinator.ui.skeletonTimeline?["experiences"].array ?? []
            )
        }

        // Audit each section
        var sectionAudits: [[String: Any]] = []
        var actionRequired = false
        var readyCount = 0
        var incompleteCount = 0
        var missingCount = 0

        for section in enabledSections.sorted() {
            let audit = auditSection(
                section,
                knowledgeCards: knowledgeCards,
                skills: skills,
                timelineEntries: timelineEntries
            )

            sectionAudits.append(audit)

            switch audit["status"] as? String {
            case "ready":
                readyCount += 1
            case "incomplete":
                incompleteCount += 1
                actionRequired = true
            case "missing":
                missingCount += 1
                actionRequired = true
            default:
                break
            }
        }

        // Build summary
        let summary: String
        if actionRequired {
            summary = "\(readyCount) sections ready, \(incompleteCount) incomplete, \(missingCount) missing data. User input needed before generating defaults."
        } else {
            summary = "All \(readyCount) enabled sections have sufficient data. Ready to generate experience defaults."
        }

        // Build response
        let response: [String: Any] = [
            "sections": sectionAudits,
            "summary": summary,
            "actionRequired": actionRequired,
            "counts": [
                "ready": readyCount,
                "incomplete": incompleteCount,
                "missing": missingCount,
                "total": enabledSections.count
            ]
        ]

        return .immediate(JSON(response))
    }

    // MARK: - Section Auditing

    private func auditSection(
        _ section: String,
        knowledgeCards: [KnowledgeCard],
        skills: [Skill],
        timelineEntries: [JSON]
    ) -> [String: Any] {
        switch section.lowercased() {
        case "work":
            return auditWorkSection(knowledgeCards: knowledgeCards, timelineEntries: timelineEntries)
        case "education":
            return auditEducationSection(knowledgeCards: knowledgeCards, timelineEntries: timelineEntries)
        case "projects":
            return auditProjectsSection(knowledgeCards: knowledgeCards)
        case "skills":
            return auditSkillsSection(skills: skills)
        case "publications":
            return auditPublicationsSection(knowledgeCards: knowledgeCards)
        case "awards":
            return auditAwardsSection(knowledgeCards: knowledgeCards)
        case "certificates":
            return auditCertificatesSection(knowledgeCards: knowledgeCards)
        case "volunteer":
            return auditVolunteerSection(knowledgeCards: knowledgeCards, timelineEntries: timelineEntries)
        case "languages", "interests", "references":
            // These sections typically don't have KC backing - mark as ready but note no KC data
            return [
                "section": section,
                "status": "ready",
                "message": "This section is typically populated from user input, not knowledge cards.",
                "gaps": [] as [String],
                "dataCount": 0
            ]
        default:
            // Custom fields - check if any KCs mention them
            return [
                "section": section,
                "status": "ready",
                "message": "Custom field - will be generated from overall context.",
                "gaps": [] as [String],
                "dataCount": 0
            ]
        }
    }

    private func auditWorkSection(knowledgeCards: [KnowledgeCard], timelineEntries: [JSON]) -> [String: Any] {
        let workKCs = knowledgeCards.filter { $0.cardType == .employment }
        let workEntries = timelineEntries.filter { $0["type"].stringValue.lowercased() == "work" }

        var gaps: [String] = []

        if workEntries.isEmpty {
            return [
                "section": "work",
                "status": "missing",
                "message": "No work entries in timeline. Cannot generate work section.",
                "gaps": ["No work history in timeline"],
                "dataCount": 0
            ]
        }

        // Check if we have KCs for each work entry
        let entriesWithoutKCs = workEntries.filter { entry in
            let org = entry["organization"].stringValue.lowercased()
            return !workKCs.contains { kc in
                kc.organization?.lowercased().contains(org) == true ||
                org.contains(kc.organization?.lowercased() ?? "")
            }
        }

        if !entriesWithoutKCs.isEmpty {
            let missingOrgs = entriesWithoutKCs.compactMap { $0["organization"].string }
            gaps.append("No KCs for: \(missingOrgs.joined(separator: ", "))")
        }

        let status: String
        let message: String

        if workKCs.isEmpty {
            status = "incomplete"
            message = "Work entries exist but no employment KCs found. Highlights will be generic."
        } else if !gaps.isEmpty {
            status = "incomplete"
            message = "Some work entries lack detailed KC coverage. \(workKCs.count) KCs for \(workEntries.count) entries."
        } else {
            status = "ready"
            message = "\(workKCs.count) employment KCs covering \(workEntries.count) work entries."
        }

        return [
            "section": "work",
            "status": status,
            "message": message,
            "gaps": gaps,
            "dataCount": workKCs.count,
            "timelineCount": workEntries.count
        ]
    }

    private func auditEducationSection(knowledgeCards: [KnowledgeCard], timelineEntries: [JSON]) -> [String: Any] {
        let educationKCs = knowledgeCards.filter { $0.cardType == .education }
        let educationEntries = timelineEntries.filter { $0["type"].stringValue.lowercased() == "education" }

        if educationEntries.isEmpty && educationKCs.isEmpty {
            return [
                "section": "education",
                "status": "missing",
                "message": "No education data found in timeline or KCs.",
                "gaps": ["No education history"],
                "dataCount": 0
            ]
        }

        // Education often doesn't need extensive KCs - timeline data is usually sufficient
        return [
            "section": "education",
            "status": "ready",
            "message": "\(educationEntries.count) education entries, \(educationKCs.count) education KCs.",
            "gaps": [] as [String],
            "dataCount": educationKCs.count,
            "timelineCount": educationEntries.count
        ]
    }

    private func auditProjectsSection(knowledgeCards: [KnowledgeCard]) -> [String: Any] {
        let projectKCs = knowledgeCards.filter { $0.cardType == .project }

        if projectKCs.isEmpty {
            return [
                "section": "projects",
                "status": "incomplete",
                "message": "No project KCs found. Projects section will be empty or minimal.",
                "gaps": ["No project knowledge cards"],
                "dataCount": 0,
                "suggestion": "Ask user about notable projects or check if project details are in employment KCs."
            ]
        }

        return [
            "section": "projects",
            "status": "ready",
            "message": "\(projectKCs.count) project KCs available.",
            "gaps": [] as [String],
            "dataCount": projectKCs.count
        ]
    }

    private func auditSkillsSection(skills: [Skill]) -> [String: Any] {
        if skills.isEmpty {
            return [
                "section": "skills",
                "status": "missing",
                "message": "No skills in skill bank. Cannot generate skills section.",
                "gaps": ["Empty skill bank"],
                "dataCount": 0
            ]
        }

        // Check category distribution
        let byCategory = Dictionary(grouping: skills, by: { $0.category })
        let smallCategories = byCategory.filter { $0.value.count < 3 }.keys

        var gaps: [String] = []
        if smallCategories.count > 3 {
            gaps.append("Several skill categories have fewer than 3 skills")
        }

        let expertSkills = skills.filter { $0.proficiency == .expert }
        if expertSkills.isEmpty {
            gaps.append("No skills marked as 'expert' level")
        }

        let status = gaps.isEmpty ? "ready" : "incomplete"
        let message = "\(skills.count) skills across \(byCategory.count) categories. \(expertSkills.count) expert-level."

        return [
            "section": "skills",
            "status": status,
            "message": message,
            "gaps": gaps,
            "dataCount": skills.count,
            "categoryCount": byCategory.count
        ]
    }

    private func auditPublicationsSection(knowledgeCards: [KnowledgeCard]) -> [String: Any] {
        // Publications are typically achievement-type KCs or need explicit data
        let achievementKCs = knowledgeCards.filter { $0.cardType == .achievement }
        let publicationKCs = achievementKCs.filter { kc in
            kc.title.lowercased().contains("publication") ||
            kc.title.lowercased().contains("paper") ||
            kc.title.lowercased().contains("journal") ||
            kc.narrative.lowercased().contains("published")
        }

        if publicationKCs.isEmpty {
            return [
                "section": "publications",
                "status": "missing",
                "message": "No publication data found in knowledge cards.",
                "gaps": ["No publication knowledge cards"],
                "dataCount": 0,
                "suggestion": "Ask user to provide publication list or offer to search Google Scholar/ORCID."
            ]
        }

        return [
            "section": "publications",
            "status": "ready",
            "message": "\(publicationKCs.count) publication-related KCs found.",
            "gaps": [] as [String],
            "dataCount": publicationKCs.count
        ]
    }

    private func auditAwardsSection(knowledgeCards: [KnowledgeCard]) -> [String: Any] {
        let achievementKCs = knowledgeCards.filter { $0.cardType == .achievement }
        let awardKCs = achievementKCs.filter { kc in
            kc.title.lowercased().contains("award") ||
            kc.title.lowercased().contains("recognition") ||
            kc.title.lowercased().contains("honor") ||
            kc.title.lowercased().contains("prize")
        }

        if awardKCs.isEmpty && achievementKCs.isEmpty {
            return [
                "section": "awards",
                "status": "missing",
                "message": "No awards or achievements found in knowledge cards.",
                "gaps": ["No award knowledge cards"],
                "dataCount": 0,
                "suggestion": "Ask user about awards, honors, or recognitions they've received."
            ]
        }

        let count = awardKCs.isEmpty ? achievementKCs.count : awardKCs.count
        return [
            "section": "awards",
            "status": awardKCs.isEmpty ? "incomplete" : "ready",
            "message": awardKCs.isEmpty
                ? "\(achievementKCs.count) achievement KCs found but none explicitly about awards."
                : "\(awardKCs.count) award-related KCs found.",
            "gaps": awardKCs.isEmpty ? ["No explicit award KCs"] : [],
            "dataCount": count
        ]
    }

    private func auditCertificatesSection(knowledgeCards: [KnowledgeCard]) -> [String: Any] {
        let achievementKCs = knowledgeCards.filter { $0.cardType == .achievement }
        let certKCs = achievementKCs.filter { kc in
            kc.title.lowercased().contains("certif") ||
            kc.title.lowercased().contains("credential") ||
            kc.title.lowercased().contains("license")
        }

        // Also check education KCs for certifications
        let educationKCs = knowledgeCards.filter { $0.cardType == .education }
        let eduCertKCs = educationKCs.filter { kc in
            kc.title.lowercased().contains("certif") ||
            kc.studyType?.lowercased().contains("certif") == true
        }

        let totalCerts = certKCs.count + eduCertKCs.count

        if totalCerts == 0 {
            return [
                "section": "certificates",
                "status": "missing",
                "message": "No certification data found.",
                "gaps": ["No certificate knowledge cards"],
                "dataCount": 0,
                "suggestion": "Ask user about professional certifications or credentials."
            ]
        }

        return [
            "section": "certificates",
            "status": "ready",
            "message": "\(totalCerts) certification-related KCs found.",
            "gaps": [] as [String],
            "dataCount": totalCerts
        ]
    }

    private func auditVolunteerSection(knowledgeCards: [KnowledgeCard], timelineEntries: [JSON]) -> [String: Any] {
        let volunteerEntries = timelineEntries.filter { $0["type"].stringValue.lowercased() == "volunteer" }

        // Volunteer could be in employment KCs too
        let volunteerKCs = knowledgeCards.filter { kc in
            kc.organization?.lowercased().contains("volunteer") == true ||
            kc.narrative.lowercased().contains("volunteer") ||
            kc.narrative.lowercased().contains("nonprofit") ||
            kc.narrative.lowercased().contains("non-profit")
        }

        if volunteerEntries.isEmpty && volunteerKCs.isEmpty {
            return [
                "section": "volunteer",
                "status": "missing",
                "message": "No volunteer experience found.",
                "gaps": ["No volunteer timeline entries or KCs"],
                "dataCount": 0,
                "suggestion": "Ask user about volunteer work or community involvement."
            ]
        }

        return [
            "section": "volunteer",
            "status": "ready",
            "message": "\(volunteerEntries.count) volunteer entries, \(volunteerKCs.count) related KCs.",
            "gaps": [] as [String],
            "dataCount": volunteerKCs.count,
            "timelineCount": volunteerEntries.count
        ]
    }
}

// MARK: - KnowledgeCard Extension for studyType

private extension KnowledgeCard {
    /// Extracts study type from education cards if available in facts
    var studyType: String? {
        facts.first { $0.category.lowercased() == "degree" || $0.category.lowercased() == "study type" }?.statement
    }
}
