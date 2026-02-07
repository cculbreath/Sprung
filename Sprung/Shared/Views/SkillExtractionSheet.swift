//
//  SkillExtractionSheet.swift
//  Sprung
//
//  Sheet for extracting skills from archived artifacts using AI.
//  Presents artifact selection, model picker, and post-processing options.
//

import SwiftUI

struct SkillExtractionSheet: View {
    let skillStore: SkillStore
    let llmFacade: LLMFacade
    let artifactRecordStore: ArtifactRecordStore
    var onComplete: ((Int, Bool, SkillCurationPlan?) -> Void)?

    @Environment(\.dismiss) private var dismiss

    // Model selection (Gemini backend, same key as SkillBankService)
    @AppStorage("skillBankModelId") private var skillBankModelId: String = ""
    @State private var geminiModels: [GoogleAIService.GeminiModel] = []
    @State private var isLoadingModels = false

    // Artifact selection
    @State private var selectedArtifactIds: Set<UUID> = []

    // Options
    @State private var clearExistingSkills = false
    @State private var runDedupeAfter = true
    @State private var runCurationAfter = false

    // Progress
    @State private var isExtracting = false
    @State private var extractionProgress: Double = 0
    @State private var extractionMessage = ""
    @State private var errorMessage: String?

    // Confirmation dialog for destructive clear
    @State private var showClearConfirmation = false

    // Jump to KC ingest
    @State private var showDocumentIngestion = false

    private var archivedArtifacts: [ArtifactRecord] {
        artifactRecordStore.archivedArtifacts
    }

    private var hasGeminiKey: Bool {
        APIKeyManager.get(.gemini) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            ScrollView {
                contentSection
            }
            Divider()
            footerSection
        }
        .frame(width: 560, height: 560)
        .onAppear {
            loadModels()
        }
        .confirmationDialog(
            "Clear All Skills?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear \(skillStore.skills.count) Skills and Extract", role: .destructive) {
                performExtraction()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all \(skillStore.skills.count) existing skills before importing extracted ones.")
        }
        .sheet(isPresented: $showDocumentIngestion) {
            DocumentIngestionSheet()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Extract Skills from Artifacts")
                    .font(.headline)
                Text("Select documents to extract skills using AI")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(spacing: 16) {
            modelPickerSection
            artifactListSection
            optionsSection

            if isExtracting {
                progressSection
            }
        }
        .padding()
    }

    // MARK: - Model Picker

    private var modelPickerSection: some View {
        GroupBox("Extraction Model") {
            if !hasGeminiKey {
                Text("No Gemini API key configured")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else if isLoadingModels {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading models...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if geminiModels.isEmpty {
                Text("No models available")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                let selectedModel = geminiModels.first { $0.id == skillBankModelId }
                Menu {
                    ForEach(geminiModels) { model in
                        Button(model.displayName) {
                            skillBankModelId = model.id
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedModel?.displayName ?? "Select model...")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
            }
        }
        .disabled(isExtracting)
    }

    // MARK: - Artifact List

    private var artifactListSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                // Header with select all and import button
                HStack {
                    Text("Archived Artifacts")
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    if !archivedArtifacts.isEmpty {
                        Button(selectedArtifactIds.count == archivedArtifacts.count ? "Deselect All" : "Select All") {
                            if selectedArtifactIds.count == archivedArtifacts.count {
                                selectedArtifactIds.removeAll()
                            } else {
                                selectedArtifactIds = Set(archivedArtifacts.map(\.id))
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }

                    Text("\(selectedArtifactIds.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if archivedArtifacts.isEmpty {
                    emptyArtifactsView
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(archivedArtifacts, id: \.id) { artifact in
                                artifactRow(artifact)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }

                // Import new artifact button
                HStack {
                    Button {
                        showDocumentIngestion = true
                    } label: {
                        Label("Import New Artifact...", systemImage: "doc.badge.plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isExtracting)

                    Spacer()
                }
            }
        }
        .disabled(isExtracting)
    }

    private func artifactRow(_ artifact: ArtifactRecord) -> some View {
        let isSelected = selectedArtifactIds.contains(artifact.id)
        return Button {
            if isSelected {
                selectedArtifactIds.remove(artifact.id)
            } else {
                selectedArtifactIds.insert(artifact.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)

                Image(systemName: artifactIcon(artifact))
                    .foregroundStyle(artifactIconColor(artifact))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(artifact.sourceType)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if !artifact.extractedContent.isEmpty {
                            Text("\(artifact.extractedContent.count / 1000)K chars")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyArtifactsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No archived artifacts")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Import documents via Knowledge Card ingestion first")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
    }

    // MARK: - Options

    private var optionsSection: some View {
        GroupBox("Options") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Clear existing skills before import", isOn: $clearExistingSkills)
                    .help("Remove all current skills before importing extracted ones")
                Toggle("Run deduplication after import", isOn: $runDedupeAfter)
                    .help("Merge semantically equivalent skills after extraction")
                Toggle("Run full curation after import", isOn: $runCurationAfter)
                    .help("Comprehensive AI review: dedup, rebalance categories, flag granular entries")
            }
        }
        .disabled(isExtracting)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: extractionProgress)
            Text(extractionMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isExtracting)
            Button("Extract Skills") {
                if clearExistingSkills && !skillStore.skills.isEmpty {
                    showClearConfirmation = true
                } else {
                    performExtraction()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedArtifactIds.isEmpty || isExtracting || skillBankModelId.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Actions

    private func loadModels() {
        guard hasGeminiKey else { return }
        isLoadingModels = true
        Task {
            do {
                let service = GoogleAIService()
                let models = try await service.fetchAvailableModels()
                await MainActor.run {
                    geminiModels = models.filter { $0.outputTokenLimit >= 16000 }
                    isLoadingModels = false
                }
            } catch {
                await MainActor.run {
                    isLoadingModels = false
                }
            }
        }
    }

    private func performExtraction() {
        let selectedArtifacts = archivedArtifacts.filter { selectedArtifactIds.contains($0.id) }
        guard !selectedArtifacts.isEmpty else { return }

        isExtracting = true
        extractionProgress = 0
        extractionMessage = "Preparing..."
        errorMessage = nil

        Task {
            do {
                // Step 1: Clear if requested
                if clearExistingSkills {
                    await MainActor.run {
                        extractionMessage = "Clearing existing skills..."
                    }
                    let existing = skillStore.skills
                    skillStore.deleteAll(existing)
                }

                // Step 2: Extract from each artifact
                let skillBankService = SkillBankService(llmFacade: llmFacade)
                var allExtracted: [Skill] = []
                let total = selectedArtifacts.count

                for (index, artifact) in selectedArtifacts.enumerated() {
                    await MainActor.run {
                        extractionMessage = "Extracting from \(artifact.displayName) (\(index + 1)/\(total))..."
                        extractionProgress = Double(index) / Double(total)
                    }

                    let content = artifact.extractedContent
                    guard !content.isEmpty else { continue }

                    let skills = try await skillBankService.extractSkills(
                        documentId: artifact.id.uuidString,
                        filename: artifact.filename,
                        content: content
                    )
                    allExtracted.append(contentsOf: skills)
                }

                // Step 3: Add to store
                await MainActor.run {
                    extractionMessage = "Adding \(allExtracted.count) skills..."
                    extractionProgress = 0.8
                }

                let newSkills = allExtracted.map { skill in
                    Skill(
                        canonical: skill.canonical,
                        atsVariants: skill.atsVariants,
                        category: skill.category,
                        proficiency: skill.proficiency,
                        evidence: skill.evidence,
                        relatedSkills: skill.relatedSkills,
                        lastUsed: skill.lastUsed,
                        isFromOnboarding: false,
                        isPending: false
                    )
                }
                await MainActor.run {
                    skillStore.addAll(newSkills)
                }

                let extractedCount = newSkills.count

                // Step 4: Post-processing
                var curationPlan: SkillCurationPlan?

                if runDedupeAfter {
                    await MainActor.run {
                        extractionMessage = "Deduplicating skills..."
                        extractionProgress = 0.85
                    }
                    let processingService = SkillsProcessingService(
                        skillStore: skillStore, facade: llmFacade
                    )
                    let _ = try await processingService.consolidateDuplicates()
                }

                if runCurationAfter {
                    await MainActor.run {
                        extractionMessage = "Generating curation plan..."
                        extractionProgress = 0.92
                    }
                    let curationService = SkillBankCurationService(
                        skillStore: skillStore, llmFacade: llmFacade
                    )
                    let plan = try await curationService.generateCurationPlan()
                    if !plan.isEmpty {
                        curationPlan = plan
                    }
                }

                await MainActor.run {
                    extractionProgress = 1.0
                    let ranPostProcessing = runDedupeAfter || runCurationAfter
                    onComplete?(extractedCount, ranPostProcessing, curationPlan)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExtracting = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func artifactIcon(_ artifact: ArtifactRecord) -> String {
        switch artifact.sourceType {
        case "git_repository": return "chevron.left.forwardslash.chevron.right"
        case "pdf": return "doc.richtext.fill"
        case "docx", "doc": return "doc.fill"
        default: return "doc.text.fill"
        }
    }

    private func artifactIconColor(_ artifact: ArtifactRecord) -> Color {
        artifact.sourceType == "git_repository" ? .orange : .blue
    }
}
