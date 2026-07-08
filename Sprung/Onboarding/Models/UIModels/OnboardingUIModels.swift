import Foundation
import SwiftyJSON

/// State for the applicant profile intake flow
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

/// Tracks which type of card is currently visible in the ToolPane
enum OnboardingToolPaneCard: String, Codable {
    case none
    case choicePrompt
    case validationPrompt
    case uploadRequest
    case applicantProfileRequest
    case applicantProfileIntake
    case sectionToggle
    case editTimelineCards
    case confirmTimelineCards
}

/// Request to display applicant profile for review
struct OnboardingApplicantProfileRequest {
    var proposedProfile: JSON
    var sources: [String]
}

/// Request to configure enabled sections
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
        self.proposedSections = Self.normalizedIdentifiers(from: proposedSections)
        self.availableSections = Self.normalizedIdentifiers(from: availableSections)
        self.rationale = rationale
    }

    private static func normalizedIdentifiers(from identifiers: [String]) -> [String] {
        var seen: Set<String> = []
        return identifiers.compactMap { identifier in
            ExperienceSectionKey.fromOnboardingIdentifier(identifier)?.rawValue
        }.filter { seen.insert($0).inserted }
    }
}

/// Tracks a pending extraction operation
struct OnboardingPendingExtraction: Identifiable {
    var id: UUID
    var title: String
    var progressItems: [ExtractionProgressItem]

    mutating func ensureProgressItems() {
        if progressItems.isEmpty {
            progressItems = ExtractionProgressStage.defaultItems()
        }
    }

    mutating func applyProgressUpdate(_ update: ExtractionProgressUpdate) {
        ensureProgressItems()
        guard let index = progressItems.firstIndex(where: { $0.stage == update.stage }) else { return }
        if update.state == .active {
            for idx in progressItems.indices where idx != index && progressItems[idx].state == .active {
                progressItems[idx].state = .completed
            }
        }
        if update.state == .completed {
            let targetOrder = update.stage.order
            for idx in progressItems.indices where progressItems[idx].stage.order < targetOrder {
                if progressItems[idx].state == .pending {
                    progressItems[idx].state = .completed
                }
            }
        }
        progressItems[index].state = update.state
        if let detail = update.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            progressItems[index].detail = detail
        } else if update.state == .pending {
            progressItems[index].detail = nil
        }
    }
}
