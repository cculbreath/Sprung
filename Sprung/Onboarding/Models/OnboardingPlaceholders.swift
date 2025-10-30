//
//  OnboardingPlaceholders.swift
//  Sprung
//
//  Minimal data models to support the onboarding interview UI during the M0
//  skeleton milestone. These will be expanded in later milestones.
//

import Foundation
import SwiftyJSON

enum OnboardingMessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct OnboardingMessage: Identifiable, Codable {
    let id: UUID
    let role: OnboardingMessageRole
    var text: String
    let timestamp: Date
    var reasoningSummary: String?

    init(
        id: UUID = UUID(),
        role: OnboardingMessageRole,
        text: String,
        timestamp: Date = Date(),
        reasoningSummary: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.reasoningSummary = reasoningSummary
    }
}

enum OnboardingSelectionStyle: String, Codable {
    case single
    case multiple
}

struct OnboardingChoiceOption: Identifiable, Codable {
    let id: String
    let title: String
    let detail: String?
    let icon: String?
}

struct OnboardingChoicePrompt: Identifiable, Codable {
    let id: UUID
    let prompt: String
    let options: [OnboardingChoiceOption]
    let selectionStyle: OnboardingSelectionStyle
    let required: Bool
}

enum OnboardingWizardStep: String, CaseIterable, Hashable, Codable {
    case introduction = "Introduction"
    case resumeIntake = "Résumé Intake"
    case artifactDiscovery = "Artifact Discovery"
    case writingCorpus = "Writing Corpus"
    case wrapUp = "Wrap Up"

    var title: String { rawValue }
}

enum OnboardingWizardStepStatus: String, Codable {
    case pending
    case current
    case completed
}

struct OnboardingQuestion: Identifiable, Codable {
    let id: UUID
    let text: String
}

struct OnboardingUploadMetadata: Codable {
    var title: String
    var instructions: String
    var accepts: [String]
    var allowMultiple: Bool
    var allowURL: Bool = true
    var targetKey: String?
}

enum OnboardingUploadKind: String, CaseIterable, Codable {
    case resume
    case linkedIn
    case artifact
    case generic
    case writingSample
    case coverletter
    case portfolio
    case transcript
    case certificate
}

struct OnboardingUploadRequest: Identifiable, Codable {
    let id: UUID
    let kind: OnboardingUploadKind
    let metadata: OnboardingUploadMetadata
}

struct OnboardingUploadedItem: Identifiable, Codable {
    let id: UUID
    let filename: String
    let url: URL
    let uploadedAt: Date
}

struct OnboardingArtifacts {
    var applicantProfile: JSON?
    var skeletonTimeline: JSON?
    var artifactRecords: [JSON] = []
    var enabledSections: [String] = []
    var knowledgeCards: [JSON] = []
}

struct OnboardingApplicantProfileIntakeState: Equatable {
    enum Mode: Equatable {
        case options
        case loading(String)
        case manual(source: Source)
        case urlEntry
    }

    enum Source: Equatable {
        case manual
        case contacts
    }

    var mode: Mode
    var draft: ApplicantProfileDraft
    var urlString: String
    var errorMessage: String?

    static func options() -> OnboardingApplicantProfileIntakeState {
        OnboardingApplicantProfileIntakeState(
            mode: .options,
            draft: ApplicantProfileDraft(),
            urlString: "",
            errorMessage: nil
        )
    }
}

struct OnboardingPhaseAdvanceRequest: Identifiable {
    var id: UUID
    var currentPhase: InterviewPhase
    var nextPhase: InterviewPhase
    var missingObjectives: [String]
    var reason: String?
    var proposedOverrides: [String]
}

struct OnboardingValidationPrompt: Identifiable {
    var id: UUID
    var dataType: String
    var payload: JSON
    var message: String?
}

struct OnboardingApplicantProfileRequest {
    var proposedProfile: JSON
    var sources: [String]

    init(proposedProfile: JSON, sources: [String] = []) {
        self.proposedProfile = proposedProfile
        self.sources = sources
    }
}

struct OnboardingSectionToggleRequest {
    var id: UUID
    var proposedSections: [String]
    var availableSections: [String]
    var rationale: String?

    init(
        id: UUID = UUID(),
        proposedSections: [String] = [],
        availableSections: [String] = [],
        rationale: String? = nil
    ) {
        self.id = id
        self.proposedSections = proposedSections
        self.availableSections = availableSections
        self.rationale = rationale
    }
}

struct OnboardingPendingExtraction: Identifiable {
    var id: UUID
    var title: String
    var summary: String
    var rawExtraction: JSON
    var uncertainties: [String]

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        rawExtraction: JSON = JSON(),
        uncertainties: [String] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.rawExtraction = rawExtraction
        self.uncertainties = uncertainties
    }
}
