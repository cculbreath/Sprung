//
//  ExperienceRefineSheet.swift
//  Sprung
//
//  Review sheet for single-entry AI refinement. The user types optional
//  direction, runs the SGM generator via ExperienceEntryRefinementService,
//  then accepts or rejects each proposed field/bullet. Only accepted content
//  is handed back to the editor — nothing is applied until "Apply Accepted".
//

import SwiftUI

struct ExperienceRefineSheet: View {
    let draft: ExperienceDefaultsDraft
    let request: ExperienceRefineRequest
    let current: ExperienceRefineContent
    let onApply: (ExperienceRefineContent) -> Void

    @Environment(ExperienceEntryRefinementService.self) private var service
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case input
        case loading
        case review
        case failed(message: String, recovery: String?, settingKey: String?)
    }

    @State private var feedback = ""
    @State private var phase: Phase = .input
    @State private var proposal: ExperienceRefineContent?
    @State private var acceptDescription = true
    @State private var highlightAccepted: [Bool] = []
    @State private var acceptKeywords = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if phase != .loading {
                        feedbackEditor
                    }
                    content
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 480, idealHeight: 560)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Refine with AI")
                .font(.headline)
            Text(request.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - Feedback

    private var feedbackEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Direction (optional)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $feedback)
                .font(.body)
                .frame(minHeight: 64)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
            Text("Tell the model how to revise this entry — e.g. \u{201C}lead with the platform work, keep bullets short.\u{201D} Leave blank for a fresh take.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Content (per phase)

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .input:
            EmptyView()
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Refining…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        case .review:
            reviewContent
        case let .failed(message, recovery, _):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if let recovery {
                    Text(recovery)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        if let proposal {
            VStack(alignment: .leading, spacing: 18) {
                if let proposedDescription = proposal.description {
                    descriptionSection(proposed: proposedDescription)
                }
                highlightsSection(proposed: proposal.highlights)
                if let proposedKeywords = proposal.keywords {
                    keywordsSection(proposed: proposedKeywords)
                }
            }
        }
    }

    private func descriptionSection(proposed: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Description")
            if let currentDescription = current.description, !currentDescription.trimmed().isEmpty {
                labeledBlock("Current", currentDescription, emphasized: false)
            }
            Toggle(isOn: $acceptDescription) {
                labeledBlock("Proposed", proposed, emphasized: true)
            }
            .toggleStyle(.checkbox)
        }
    }

    private func highlightsSection(proposed: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Highlights")
            if !current.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                    ForEach(current.highlights.indices, id: \.self) { i in
                        Text("• \(current.highlights[i])")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("PROPOSED")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            if proposed.isEmpty {
                Text("The model returned no highlights.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(proposed.indices, id: \.self) { index in
                    Toggle(isOn: binding(for: index)) {
                        Text(proposed[index])
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private func keywordsSection(proposed: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Keywords")
            if let currentKeywords = current.keywords, !currentKeywords.isEmpty {
                labeledBlock("Current", currentKeywords.joined(separator: ", "), emphasized: false)
            }
            Toggle(isOn: $acceptKeywords) {
                labeledBlock("Proposed", proposed.joined(separator: ", "), emphasized: true)
            }
            .toggleStyle(.checkbox)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.bold())
            .foregroundStyle(.secondary)
    }

    private func labeledBlock(_ label: String, _ value: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.body)
                .foregroundStyle(emphasized ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            switch phase {
            case .input:
                Button("Refine") { Task { await runRefine() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .loading:
                Button("Refine") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            case .review:
                Button("Retry") { Task { await runRefine() } }
                Button("Apply Accepted") { applyAccepted() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasAnyAcceptance)
            case let .failed(_, _, settingKey):
                if let settingKey {
                    Button("Open Model Settings") { openModelSettings(settingKey) }
                }
                Button("Try Again") { Task { await runRefine() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    // MARK: - Acceptance

    private func binding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { highlightAccepted.indices.contains(index) ? highlightAccepted[index] : false },
            set: { newValue in
                guard highlightAccepted.indices.contains(index) else { return }
                highlightAccepted[index] = newValue
            }
        )
    }

    private var acceptedHighlights: [String] {
        guard let proposal else { return [] }
        return zip(proposal.highlights, highlightAccepted)
            .filter { $0.1 }
            .map { $0.0 }
    }

    private var hasAnyAcceptance: Bool {
        guard let proposal else { return false }
        let descAccepted = proposal.description != nil && acceptDescription
        let keywordsAccepted = proposal.keywords != nil && acceptKeywords
        return descAccepted || keywordsAccepted || !acceptedHighlights.isEmpty
    }

    private func applyAccepted() {
        guard let proposal else { return }
        let accepted = ExperienceRefineContent(
            description: (proposal.description != nil && acceptDescription) ? proposal.description : nil,
            highlights: acceptedHighlights,
            keywords: (proposal.keywords != nil && acceptKeywords) ? proposal.keywords : nil
        )
        onApply(accepted)
        dismiss()
    }

    // MARK: - Actions

    private func runRefine() async {
        phase = .loading
        do {
            let result = try await service.refine(
                kind: request.kind,
                entryID: request.entryID,
                current: current,
                draft: draft,
                feedback: feedback
            )
            proposal = result
            acceptDescription = true
            acceptKeywords = true
            highlightAccepted = Array(repeating: true, count: result.highlights.count)
            phase = .review
        } catch let error as ModelConfigurationError {
            phase = .failed(
                message: error.errorDescription ?? "A model must be configured first.",
                recovery: error.recoverySuggestion,
                settingKey: error.settingKey
            )
        } catch {
            phase = .failed(message: error.localizedDescription, recovery: nil, settingKey: nil)
        }
    }

    private func openModelSettings(_ settingKey: String) {
        NotificationCenter.default.post(
            name: .showModelSettings,
            object: nil,
            userInfo: ["settingKey": settingKey]
        )
        dismiss()
    }
}
