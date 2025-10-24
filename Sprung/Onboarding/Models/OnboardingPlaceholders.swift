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
    let text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: OnboardingMessageRole, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
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

    init(
        id: UUID = UUID(),
        prompt: String,
        options: [OnboardingChoiceOption],
        selectionStyle: OnboardingSelectionStyle,
        required: Bool
    ) {
        self.id = id
        self.prompt = prompt
        self.options = options
        self.selectionStyle = selectionStyle
        self.required = required
    }
}

enum OnboardingWizardStep: String, CaseIterable, Hashable, Codable {
    case introduction
    case resumeIntake
    case artifactDiscovery
    case writingCorpus
    case wrapUp
}

enum OnboardingWizardStepStatus: String, Codable {
    case pending
    case current
    case completed
}

struct OnboardingQuestion: Identifiable, Codable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct OnboardingUploadMetadata: Codable {
    var title: String
    var instructions: String
    var accepts: [String]
    var allowMultiple: Bool
}

enum OnboardingUploadKind: String, Codable {
    case resume
    case linkedIn
    case artifact
    case generic
    case writingSample
}

struct OnboardingUploadRequest: Identifiable, Codable {
    let id: UUID
    let kind: OnboardingUploadKind
    let metadata: OnboardingUploadMetadata

    init(id: UUID = UUID(), kind: OnboardingUploadKind, metadata: OnboardingUploadMetadata) {
        self.id = id
        self.kind = kind
        self.metadata = metadata
    }
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
    var items: [String] = []
}

struct OnboardingContactsFetchRequest: Codable {
    var message: String
}

struct OnboardingValidationPrompt: Identifiable {
    var id: UUID
    var dataType: String
    var payload: JSON
    var message: String?

    init(id: UUID = UUID(), dataType: String, payload: JSON, message: String?) {
        self.id = id
        self.dataType = dataType
        self.payload = payload
        self.message = message
    }
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
    var availableSections: [String]
}

struct OnboardingSectionEntryRequest: Identifiable {
    var id: UUID
    var sectionId: String
    var proposedEntries: [JSON]
}

struct OnboardingPendingExtraction: Identifiable {
    var id: UUID
    var title: String
    var summary: String
}
