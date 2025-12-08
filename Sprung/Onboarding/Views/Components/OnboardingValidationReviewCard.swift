import SwiftUI
import SwiftyJSON
struct OnboardingValidationReviewCard: View {
    enum Decision: String, CaseIterable, Identifiable {
        case approved
        case modified
        case rejected
        var id: String { rawValue }
        var label: String {
            switch self {
            case .approved: return "Approve"
            case .modified: return "Modify"
            case .rejected: return "Reject"
            }
        }
    }
    let prompt: OnboardingValidationPrompt
    let onSubmit: (_ status: Decision, _ updated: JSON?, _ notes: String?) -> Void
    let onCancel: () -> Void
    @State private var decision: Decision
    @State private var notes: String
    @State private var updatedPayloadText: String
    @State private var errorMessage: String?
    @State private var applicantDraft: ApplicantProfileDraft
    @State private var baselineApplicantDraft: ApplicantProfileDraft
    @State private var applicantHasChanges: Bool
    private let baselineApplicantJSON: String
    @State private var timelineDraft: ExperienceDefaultsDraft
    @State private var baselineTimelineDraft: ExperienceDefaultsDraft
    @State private var timelineHasChanges: Bool
    @State private var timelineEditingEntries: Set<UUID>
    private let baselineTimelineJSON: String
    init(
        prompt: OnboardingValidationPrompt,
        onSubmit: @escaping (_ status: Decision, _ updated: JSON?, _ notes: String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _decision = State(initialValue: .approved)
        _notes = State(initialValue: "")
        _updatedPayloadText = State(initialValue: "")
        _errorMessage = State(initialValue: nil)
        if prompt.dataType == "applicant_profile" {
            let draft = ApplicantProfileDraft(json: prompt.payload)
            _applicantDraft = State(initialValue: draft)
            _baselineApplicantDraft = State(initialValue: draft)
            _applicantHasChanges = State(initialValue: false)
            baselineApplicantJSON = OnboardingValidationReviewCard.normalizedJSONString(from: prompt.payload)
        } else {
            let emptyDraft = ApplicantProfileDraft()
            _applicantDraft = State(initialValue: emptyDraft)
            _baselineApplicantDraft = State(initialValue: emptyDraft)
            _applicantHasChanges = State(initialValue: false)
            baselineApplicantJSON = ""
        }
        if prompt.dataType == "skeleton_timeline" {
            let draft = ExperienceDefaultsDecoder.draft(from: prompt.payload)
            _timelineDraft = State(initialValue: draft)
            _baselineTimelineDraft = State(initialValue: draft)
            _timelineHasChanges = State(initialValue: false)
            _timelineEditingEntries = State(initialValue: [])
            baselineTimelineJSON = OnboardingValidationReviewCard.normalizedJSONString(from: OnboardingValidationReviewCard.timelineJSON(from: draft))
        } else {
            let emptyDraft = ExperienceDefaultsDraft()
            _timelineDraft = State(initialValue: emptyDraft)
            _baselineTimelineDraft = State(initialValue: emptyDraft)
            _timelineHasChanges = State(initialValue: false)
            _timelineEditingEntries = State(initialValue: [])
            baselineTimelineJSON = ""
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("Review \(displayTitle)")
                .font(.headline)
            if let message = prompt.message, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Scrollable content area
            ScrollView {
                contentView
            }
            .frame(maxHeight: 280)

            // Sticky footer - always visible
            VStack(alignment: .leading, spacing: 12) {
                Picker("Decision", selection: $decision) {
                    ForEach(Decision.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if shouldShowRawEditor {
                    rawJSONEditor
                } else if decision == .modified {
                    Text("Changes will be sent back to the interviewer when you submit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                notesEditor

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button("Cancel", action: onCancel)
                    Spacer()
                    Button("Submit Decision", action: submit)
                        .buttonStyle(.borderedProminent)
                        .disabled(disableSubmit)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
        .onChange(of: applicantDraft) { _, _ in
            guard isApplicantProfile, decision == .modified else { return }
            let normalized = Self.normalizedJSONString(from: applicantDraft.toJSON())
            applicantHasChanges = normalized != baselineApplicantJSON
        }
        .onChange(of: timelineDraft) { _, _ in
            guard isSkeletonTimeline, decision == .modified else { return }
            let normalized = Self.normalizedJSONString(from: Self.timelineJSON(from: timelineDraft))
            timelineHasChanges = normalized != baselineTimelineJSON
        }
        .onChange(of: decision) { _, newValue in
            if newValue == .modified {
                if !isStructuredType {
                    updatedPayloadText = prettyPayload
                }
            } else {
                resetStructuredEditors()
            }
        }
        .onAppear {
            if !isStructuredType && updatedPayloadText.isEmpty {
                updatedPayloadText = prettyPayload
            }
        }
    }
    @ViewBuilder
    private var contentView: some View {
        if isApplicantProfile {
            VStack(alignment: .leading, spacing: 12) {
                Text(decision == .modified ? "Update any fields below." : "Switch to Modify to edit these details.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ApplicantProfileEditor(
                    draft: $applicantDraft,
                    showPhotoSection: false,
                    showsSummary: false,
                    showsProfessionalLabel: false,
                    emailSuggestions: applicantDraft.suggestedEmails
                )
                .disabled(decision != .modified)
                HStack {
                    Button("Reset to Proposed") {
                        applicantDraft = baselineApplicantDraft
                        applicantHasChanges = false
                    }
                    .buttonStyle(.bordered)
                    .disabled(!applicantHasChanges)
                    Spacer()
                }
            }
        } else if isSkeletonTimeline {
            VStack(alignment: .leading, spacing: 12) {
                Text(decision == .modified ? "Adjust the generated timeline." : "Switch to Modify to make timeline changes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SkeletonTimelineReviewView(
                    draft: $timelineDraft,
                    editingEntries: $timelineEditingEntries,
                    onChange: {
                        guard decision == .modified else { return }
                        let normalized = Self.normalizedJSONString(from: Self.timelineJSON(from: timelineDraft))
                        timelineHasChanges = normalized != baselineTimelineJSON
                    }
                )
                .disabled(decision != .modified)
                HStack {
                    Button("Reset to Proposed") {
                        timelineDraft = baselineTimelineDraft
                        timelineEditingEntries.removeAll()
                        timelineHasChanges = false
                    }
                    .buttonStyle(.bordered)
                    .disabled(!timelineHasChanges)
                    Spacer()
                }
            }
        } else {
            ScrollView {
                Text(prettyPayload)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
            .frame(minHeight: 160)
        }
    }
    private var shouldShowRawEditor: Bool {
        !isStructuredType && decision == .modified
    }
    private var isApplicantProfile: Bool {
        prompt.dataType == "applicant_profile"
    }
    private var isSkeletonTimeline: Bool {
        prompt.dataType == "skeleton_timeline"
    }
    private var isStructuredType: Bool {
        isApplicantProfile || isSkeletonTimeline
    }
    private var displayTitle: String {
        prompt.dataType.replacingOccurrences(of: "_", with: " ").capitalized
    }
    private var prettyPayload: String {
        if let data = try? prompt.payload.rawData(options: [.prettyPrinted]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return prompt.payload.description
    }
    private var rawJSONEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provide updated JSON")
                .font(.headline)
            TextEditor(text: $updatedPayloadText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )
        }
    }
    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes (optional)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .frame(height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )
        }
    }
    private var disableSubmit: Bool {
        if decision == .modified {
            if isApplicantProfile { return false }
            if isSkeletonTimeline { return false }
            return updatedPayloadText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
    private func resetStructuredEditors() {
        if isApplicantProfile {
            applicantDraft = baselineApplicantDraft
            applicantHasChanges = false
        }
        if isSkeletonTimeline {
            timelineDraft = baselineTimelineDraft
            timelineEditingEntries.removeAll()
            timelineHasChanges = false
        }
    }
    private func submit() {
        var updatedJSON: JSON?
        switch decision {
        case .approved:
            updatedJSON = nil
        case .rejected:
            updatedJSON = nil
        case .modified:
            if isApplicantProfile {
                updatedJSON = applicantDraft.toJSON()
            } else if isSkeletonTimeline {
                updatedJSON = Self.timelineJSON(from: timelineDraft)
            } else {
                let trimmed = updatedPayloadText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    errorMessage = "Provide updated JSON or choose a different decision."
                    return
                }
                let parsed = JSON(parseJSON: trimmed)
                guard parsed != .null else {
                    errorMessage = "The modified JSON could not be parsed. Please verify the syntax."
                    return
                }
                updatedJSON = parsed
            }
        }
        errorMessage = nil
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        onSubmit(decision, updatedJSON, trimmedNotes.isEmpty ? nil : trimmedNotes)
        updatedPayloadText = ""
        notes = ""
    }
    private static func normalizedJSONString(from json: JSON) -> String {
        json.rawString(options: .sortedKeys) ?? json.rawString() ?? ""
    }
    private static func timelineJSON(from draft: ExperienceDefaultsDraft) -> JSON {
        let dictionary = ExperienceDefaultsEncoder.makeSeedDictionary(from: draft)
        return JSON(dictionary)
    }
}
