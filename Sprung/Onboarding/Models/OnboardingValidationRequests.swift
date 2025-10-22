import Foundation
import SwiftyJSON

enum OnboardingSelectionStyle: String {
    case single
    case multiple
}

struct OnboardingChoiceOption: Identifiable, Equatable {
    enum ControlStyle: String {
        case radio
        case checkbox
        case button
    }

    let id: String
    let title: String
    let detail: String?
    let controlStyle: ControlStyle

    init(id: String, title: String, detail: String?, controlStyle: ControlStyle = .radio) {
        self.id = id
        self.title = title
        self.detail = detail
        self.controlStyle = controlStyle
    }

    init(json: JSON) {
        let identifier = json["id"].string ??
            json["value"].string ??
            UUID().uuidString
        let title = json["title"].string ??
            json["label"].string ??
            identifier
        let detail = json["detail"].string ?? json["description"].string
        let styleRaw = json["style"].string?.lowercased()
        let style = ControlStyle(rawValue: styleRaw ?? "") ?? .radio
        self.init(id: identifier, title: title, detail: detail, controlStyle: style)
    }
}

struct OnboardingChoicePrompt: Identifiable, Equatable {
    let id: UUID
    let toolCallId: String
    let prompt: String
    let selectionStyle: OnboardingSelectionStyle
    let options: [OnboardingChoiceOption]
    let allowCancel: Bool

    init(
        toolCallId: String,
        prompt: String,
        selectionStyle: OnboardingSelectionStyle,
        options: [OnboardingChoiceOption],
        allowCancel: Bool
    ) {
        self.id = UUID()
        self.toolCallId = toolCallId
        self.prompt = prompt
        self.selectionStyle = selectionStyle
        self.options = options
        self.allowCancel = allowCancel
    }

    static func fromToolCall(_ call: OnboardingToolCall) -> OnboardingChoicePrompt {
        let prompt = call.arguments["prompt"].string ??
            call.arguments["question"].string ??
            "Please make a selection."
        let style = OnboardingSelectionStyle(rawValue: call.arguments["selection_style"].stringValue.lowercased()) ?? .single
        let allowCancel = call.arguments["allow_cancel"].bool ?? true
        let optionsJSON = call.arguments["options"].arrayValue
        let options = optionsJSON.map(OnboardingChoiceOption.init(json:))
        return OnboardingChoicePrompt(
            toolCallId: call.identifier,
            prompt: prompt,
            selectionStyle: style,
            options: options,
            allowCancel: allowCancel
        )
    }
}

struct OnboardingApplicantProfileRequest: Identifiable, Equatable {
    let id: UUID
    let toolCallId: String
    let proposedProfile: JSON
    let sources: [String]

    init(toolCallId: String, proposedProfile: JSON, sources: [String]) {
        self.id = UUID()
        self.toolCallId = toolCallId
        self.proposedProfile = proposedProfile
        self.sources = sources
    }

    static func fromToolCall(_ call: OnboardingToolCall) -> OnboardingApplicantProfileRequest {
        let proposed = call.arguments["profile"]
        let sources = call.arguments["sources"].arrayValue.compactMap { $0.string }
        return OnboardingApplicantProfileRequest(
            toolCallId: call.identifier,
            proposedProfile: proposed,
            sources: sources
        )
    }
}

struct OnboardingSectionToggleRequest: Identifiable, Equatable {
    let id: UUID
    let toolCallId: String
    let proposedSections: [String]
    let rationale: String?

    init(toolCallId: String, proposedSections: [String], rationale: String?) {
        self.id = UUID()
        self.toolCallId = toolCallId
        self.proposedSections = proposedSections
        self.rationale = rationale
    }

    static func fromToolCall(_ call: OnboardingToolCall) -> OnboardingSectionToggleRequest {
        let sectionValues = call.arguments["sections"].arrayValue
            .compactMap { $0.string?.lowercased() }
        let enabledValues = call.arguments["enabledSections"].arrayValue
            .compactMap { $0.string?.lowercased() }
        let sections = Array(Set(sectionValues + enabledValues)).sorted()
        let rationale = call.arguments["rationale"].string ?? call.arguments["notes"].string
        return OnboardingSectionToggleRequest(
            toolCallId: call.identifier,
            proposedSections: sections,
            rationale: rationale
        )
    }
}

struct OnboardingSectionEntryRequest: Identifiable, Equatable {
    enum Mode: String {
        case create
        case update
    }

    let id: UUID
    let toolCallId: String
    let section: String
    let mode: Mode
    let entries: [JSON]
    let context: String?

    init(
        toolCallId: String,
        section: String,
        mode: Mode,
        entries: [JSON],
        context: String?
    ) {
        self.id = UUID()
        self.toolCallId = toolCallId
        self.section = section
        self.mode = mode
        self.entries = entries
        self.context = context
    }

    static func fromToolCall(_ call: OnboardingToolCall) -> OnboardingSectionEntryRequest {
        let section = call.arguments["section"].stringValue.lowercased()
        let modeRaw = call.arguments["mode"].stringValue.lowercased()
        let mode = Mode(rawValue: modeRaw) ?? .create
        let entries = call.arguments["entries"].arrayValue
        let context = call.arguments["context"].string ?? call.arguments["notes"].string
        return OnboardingSectionEntryRequest(
            toolCallId: call.identifier,
            section: section,
            mode: mode,
            entries: entries,
            context: context
        )
    }
}

struct OnboardingContactsFetchRequest: Identifiable, Equatable {
    let id: UUID
    let toolCallId: String
    let requestedFields: [String]

    init(toolCallId: String, requestedFields: [String]) {
        self.id = UUID()
        self.toolCallId = toolCallId
        self.requestedFields = requestedFields
    }

    static func fromToolCall(_ call: OnboardingToolCall) -> OnboardingContactsFetchRequest {
        let fields = call.arguments["fields"].arrayValue.compactMap { $0.string?.lowercased() }
        return OnboardingContactsFetchRequest(toolCallId: call.identifier, requestedFields: fields)
    }
}
