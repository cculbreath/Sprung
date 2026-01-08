import Foundation
import SwiftyJSON

/// Selection style for choice prompts
enum OnboardingSelectionStyle: String, Codable {
    case single
    case multiple
}

/// A single option in a choice prompt
struct OnboardingChoiceOption: Identifiable, Codable {
    let id: String
    let title: String
    let detail: String?
    let icon: String?
}

/// A prompt presenting choices to the user
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

/// A prompt for validating data submitted by the LLM
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
