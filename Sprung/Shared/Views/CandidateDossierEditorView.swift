//
//  CandidateDossierEditorView.swift
//  Sprung
//
//  Editor view for the candidate dossier - qualitative context about the job seeker.
//  Displays all fields with character count validation and auto-save.
//

import SwiftUI

struct CandidateDossierEditorView: View {
    @Environment(CandidateDossierStore.self) private var dossierStore
    @Environment(\.dismiss) private var dismiss

    // MARK: - Local State (editable copies)

    @State private var jobSearchContext: String = ""
    @State private var strengthsToEmphasize: String = ""
    @State private var pitfallsToAvoid: String = ""
    @State private var workArrangementPreferences: String = ""
    @State private var availability: String = ""
    @State private var uniqueCircumstances: String = ""
    @State private var interviewerNotes: String = ""

    @State private var hasUnsavedChanges = false
    @State private var showingDiscardAlert = false
    @State private var selectedSection: DossierSection = .context

    // MARK: - Sections

    enum DossierSection: String, CaseIterable {
        case context = "Context"
        case strengths = "Strengths"
        case pitfalls = "Pitfalls"
        case preferences = "Preferences"
        case notes = "Notes"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            HSplitView {
                sectionNavigation
                    .frame(minWidth: 140, maxWidth: 160)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedSection {
                        case .context:
                            contextSection
                        case .strengths:
                            strengthsSection
                        case .pitfalls:
                            pitfallsSection
                        case .preferences:
                            preferencesSection
                        case .notes:
                            notesSection
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadFromStore)
        .alert("Discard Changes?", isPresented: $showingDiscardAlert) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes that will be lost.")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Candidate Dossier")
                    .font(.headline)
                HStack(spacing: 12) {
                    Text("\(wordCount) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !validationErrors.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("\(validationErrors.count) issue\(validationErrors.count == 1 ? "" : "s")")
                                .font(.caption)
                        }
                        .foregroundStyle(.orange)
                    } else if isComplete {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text("Complete")
                                .font(.caption)
                        }
                        .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            if hasUnsavedChanges {
                Text("Unsaved")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            }

            Button("Save") {
                saveToStore()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasUnsavedChanges)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Section Navigation

    private var sectionNavigation: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(DossierSection.allCases, id: \.self) { section in
                sectionNavButton(section)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func sectionNavButton(_ section: DossierSection) -> some View {
        let isSelected = selectedSection == section
        let hasIssue = sectionHasIssue(section)

        return Button {
            selectedSection = section
        } label: {
            HStack {
                Text(section.rawValue)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                Spacer()
                if hasIssue {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
            .foregroundStyle(isSelected ? .blue : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func sectionHasIssue(_ section: DossierSection) -> Bool {
        switch section {
        case .context:
            return !jobSearchContext.isEmpty && jobSearchContext.count < CandidateDossier.FieldMinimums.jobSearchContext
        case .strengths:
            return !strengthsToEmphasize.isEmpty && strengthsToEmphasize.count < CandidateDossier.FieldMinimums.strengthsToEmphasize
        case .pitfalls:
            return !pitfallsToAvoid.isEmpty && pitfallsToAvoid.count < CandidateDossier.FieldMinimums.pitfallsToAvoid
        case .preferences:
            return false
        case .notes:
            return !interviewerNotes.isEmpty && interviewerNotes.count < CandidateDossier.FieldMinimums.interviewerNotes
        }
    }

    // MARK: - Context Section

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Job Search Context",
                subtitle: "What are you looking for, why now, what matters most?",
                required: true
            )

            fieldEditor(
                text: $jobSearchContext,
                placeholder: "Describe target roles, industries, company types, what prompted this search, and non-negotiables...",
                minChars: CandidateDossier.FieldMinimums.jobSearchContext
            )
        }
    }

    // MARK: - Strengths Section

    private var strengthsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Strengths to Emphasize",
                subtitle: "Hidden or under-emphasized strengths with evidence and positioning guidance",
                required: false
            )

            Text("Write 2-4 paragraphs. For each strength include: what it means, specific evidence, why it differentiates you, and how to position it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            fieldEditor(
                text: $strengthsToEmphasize,
                placeholder: "Example:\n\n**Technical Leadership with Business Impact**: Beyond deep technical skills, I consistently bridge the gap between engineering and business outcomes. Evidence: Led the platform migration that reduced costs by 40%...",
                minChars: CandidateDossier.FieldMinimums.strengthsToEmphasize
            )
        }
    }

    // MARK: - Pitfalls Section

    private var pitfallsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Pitfalls to Avoid",
                subtitle: "Potential concerns with mitigation strategies",
                required: false
            )

            Text("Write 2-4 paragraphs. For each pitfall include: the concern, why it might raise questions, mitigation strategy, and talking points for interviews.")
                .font(.caption)
                .foregroundStyle(.secondary)

            fieldEditor(
                text: $pitfallsToAvoid,
                placeholder: "Example:\n\n**Career Gap (2022-2023)**: May raise questions about recent experience. Mitigation: Frame as intentional sabbatical for skill development. In interviews, address proactively...",
                minChars: CandidateDossier.FieldMinimums.pitfallsToAvoid
            )
        }
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "Work Arrangement Preferences",
                    subtitle: "Remote, hybrid, on-site preferences and flexibility",
                    required: false
                )

                fieldEditor(
                    text: $workArrangementPreferences,
                    placeholder: "Describe your ideal work arrangement and flexibility...",
                    minChars: nil,
                    height: 100
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "Availability",
                    subtitle: "Start date, notice period, constraints",
                    required: false
                )

                fieldEditor(
                    text: $availability,
                    placeholder: "When can you start? Any notice period or timing constraints?",
                    minChars: nil,
                    height: 80
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "Unique Circumstances",
                    subtitle: "Special considerations (visa, relocation, health, family) - private",
                    required: false
                )

                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text("Private - not exported to cover letters")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                fieldEditor(
                    text: $uniqueCircumstances,
                    placeholder: "Any special circumstances that affect your job search?",
                    minChars: nil,
                    height: 100
                )
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Interviewer Notes",
                subtitle: "Observations, impressions, strategic recommendations - private",
                required: false
            )

            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                Text("Private - not exported to cover letters")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            Text("Includes deal-breakers, cultural fit indicators, communication style notes, and other interviewer observations.")
                .font(.caption)
                .foregroundStyle(.secondary)

            fieldEditor(
                text: $interviewerNotes,
                placeholder: "Add notes about communication style, cultural fit indicators, deal-breakers, and other observations...",
                minChars: CandidateDossier.FieldMinimums.interviewerNotes
            )
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String, subtitle: String, required: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if required {
                    Text("Required")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func fieldEditor(text: Binding<String>, placeholder: String, minChars: Int?, height: CGFloat = 200) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                }

                TextEditor(text: text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .onChange(of: text.wrappedValue) { _, _ in
                        hasUnsavedChanges = true
                    }
            }
            .frame(minHeight: height)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(charCountColor(text: text.wrappedValue, min: minChars).opacity(0.5), lineWidth: 1)
            )

            HStack {
                Text("\(text.wrappedValue.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let min = minChars {
                    if text.wrappedValue.count < min && !text.wrappedValue.isEmpty {
                        Text("(minimum \(min))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if text.wrappedValue.count >= min {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                Text("\(text.wrappedValue.split(separator: " ").count) words")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func charCountColor(text: String, min: Int?) -> Color {
        guard let min = min, !text.isEmpty else {
            return Color(nsColor: .separatorColor)
        }
        return text.count >= min ? .green : .orange
    }

    // MARK: - Computed Properties

    private var wordCount: Int {
        let allText = [
            jobSearchContext,
            strengthsToEmphasize,
            pitfallsToAvoid,
            workArrangementPreferences,
            availability,
            uniqueCircumstances,
            interviewerNotes
        ].joined(separator: " ")

        return allText.split(separator: " ").count
    }

    private var isComplete: Bool {
        jobSearchContext.count >= CandidateDossier.FieldMinimums.jobSearchContext &&
        strengthsToEmphasize.count >= CandidateDossier.FieldMinimums.strengthsToEmphasize &&
        pitfallsToAvoid.count >= CandidateDossier.FieldMinimums.pitfallsToAvoid
    }

    private var validationErrors: [String] {
        var errors: [String] = []

        if !jobSearchContext.isEmpty && jobSearchContext.count < CandidateDossier.FieldMinimums.jobSearchContext {
            errors.append("Job search context too short")
        }
        if !strengthsToEmphasize.isEmpty && strengthsToEmphasize.count < CandidateDossier.FieldMinimums.strengthsToEmphasize {
            errors.append("Strengths to emphasize too short")
        }
        if !pitfallsToAvoid.isEmpty && pitfallsToAvoid.count < CandidateDossier.FieldMinimums.pitfallsToAvoid {
            errors.append("Pitfalls to avoid too short")
        }
        if !interviewerNotes.isEmpty && interviewerNotes.count < CandidateDossier.FieldMinimums.interviewerNotes {
            errors.append("Interviewer notes too short")
        }

        return errors
    }

    // MARK: - Store Operations

    private func loadFromStore() {
        guard let dossier = dossierStore.dossier else { return }

        jobSearchContext = dossier.jobSearchContext
        strengthsToEmphasize = dossier.strengthsToEmphasize ?? ""
        pitfallsToAvoid = dossier.pitfallsToAvoid ?? ""
        workArrangementPreferences = dossier.workArrangementPreferences ?? ""
        availability = dossier.availability ?? ""
        uniqueCircumstances = dossier.uniqueCircumstances ?? ""
        interviewerNotes = dossier.interviewerNotes ?? ""

        hasUnsavedChanges = false
    }

    private func saveToStore() {
        _ = dossierStore.upsertDossier(
            jobSearchContext: jobSearchContext,
            strengthsToEmphasize: strengthsToEmphasize.isEmpty ? nil : strengthsToEmphasize,
            pitfallsToAvoid: pitfallsToAvoid.isEmpty ? nil : pitfallsToAvoid,
            workArrangementPreferences: workArrangementPreferences.isEmpty ? nil : workArrangementPreferences,
            availability: availability.isEmpty ? nil : availability,
            uniqueCircumstances: uniqueCircumstances.isEmpty ? nil : uniqueCircumstances,
            interviewerNotes: interviewerNotes.isEmpty ? nil : interviewerNotes
        )
        hasUnsavedChanges = false
    }
}
