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
    let isSystemGenerated: Bool  // True for app-generated trigger messages
    var toolCalls: [ToolCallInfo]?  // Tool calls made in this message (for assistant messages)

    /// Represents a tool call and its result (paired storage for Anthropic compatibility)
    struct ToolCallInfo: Codable {
        let id: String
        let name: String
        let arguments: String
        /// The tool result output (filled in when the result arrives)
        /// nil means the result hasn't been received yet
        var result: String?

        /// Whether this tool call has received its result
        var isComplete: Bool { result != nil }

        init(id: String, name: String, arguments: String, result: String? = nil) {
            self.id = id
            self.name = name
            self.arguments = arguments
            self.result = result
        }
    }
    init(
        id: UUID = UUID(),
        role: OnboardingMessageRole,
        text: String,
        timestamp: Date = Date(),
        isSystemGenerated: Bool = false,
        toolCalls: [ToolCallInfo]? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.isSystemGenerated = isSystemGenerated
        self.toolCalls = toolCalls
    }

    // MARK: - Tool Result Pairing

    /// Whether all tool calls in this message have received their results
    var allToolCallsComplete: Bool {
        guard let toolCalls = toolCalls, !toolCalls.isEmpty else { return true }
        return toolCalls.allSatisfy { $0.isComplete }
    }

    /// Get IDs of tool calls that haven't received results yet
    var pendingToolCallIds: [String] {
        guard let toolCalls = toolCalls else { return [] }
        return toolCalls.filter { !$0.isComplete }.map { $0.id }
    }

    /// Update a tool call with its result
    /// - Returns: true if the tool call was found and updated
    mutating func setToolResult(callId: String, result: String) -> Bool {
        guard var toolCalls = toolCalls,
              let index = toolCalls.firstIndex(where: { $0.id == callId }) else {
            return false
        }
        toolCalls[index].result = result
        self.toolCalls = toolCalls
        return true
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
    /// Optional source identifier for special handling (e.g., "skip_phase_approval")
    let source: String?

    init(
        id: UUID = UUID(),
        prompt: String,
        options: [OnboardingChoiceOption],
        selectionStyle: OnboardingSelectionStyle,
        required: Bool,
        source: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.options = options
        self.selectionStyle = selectionStyle
        self.required = required
        self.source = source
    }
}
/// Wizard steps that correspond to the 4-phase interview structure
enum OnboardingWizardStep: String, CaseIterable, Hashable, Codable {
    case voice      // Phase 1: Voice & Context
    case story      // Phase 2: Career Story
    case evidence   // Phase 3: Evidence Collection
    case strategy   // Phase 4: Strategic Synthesis
}
enum OnboardingWizardStepStatus: String, Codable {
    case pending
    case current
    case completed
}
extension OnboardingWizardStep {
    var title: String {
        switch self {
        case .voice:
            return "Voice"
        case .story:
            return "Story"
        case .evidence:
            return "Evidence"
        case .strategy:
            return "Strategy"
        }
    }
}
struct OnboardingUploadMetadata: Codable {
    var title: String
    var instructions: String
    var accepts: [String]
    var allowMultiple: Bool
    var allowURL: Bool = true
    var targetKey: String?
    var cancelMessage: String?
    var targetPhaseObjectives: [String]?
    var targetDeliverable: String?
    var userValidated: Bool?
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
struct OnboardingValidationPrompt: Identifiable, Codable {
    enum Mode: String, Codable {
        case editor      // Editor UI (Save button, no waiting state, tools allowed)
        case validation  // Validation UI (Approve/Reject buttons, waiting state, tools blocked)
    }
    var id: UUID
    var dataType: String
    var payload: JSON
    var message: String?
    var mode: Mode
    init(id: UUID = UUID(), dataType: String, payload: JSON, message: String?, mode: Mode = .validation) {
        self.id = id
        self.dataType = dataType
        self.payload = payload
        self.message = message
        self.mode = mode
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
struct OnboardingPendingExtraction: Identifiable {
    var id: UUID
    var title: String
    var summary: String
    var rawExtraction: JSON
    var uncertainties: [String]
    var progressItems: [ExtractionProgressItem]
    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        rawExtraction: JSON = JSON(),
        uncertainties: [String] = [],
        progressItems: [ExtractionProgressItem] = ExtractionProgressStage.defaultItems()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.rawExtraction = rawExtraction
        self.uncertainties = uncertainties
        self.progressItems = progressItems.isEmpty ? ExtractionProgressStage.defaultItems() : progressItems
    }
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
