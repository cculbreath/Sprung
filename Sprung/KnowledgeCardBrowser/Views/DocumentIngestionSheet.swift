//
//  DocumentIngestionSheet.swift
//  Sprung
//
//  Sheet UI for standalone document/git repo ingestion and knowledge card generation.
//  This is an AI-powered alternative to manually creating knowledge cards -
//  users provide source documents and the AI generates comprehensive prose.
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentIngestionSheet: View {
    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore
    @Environment(LLMFacade.self) private var llmFacade
    @Environment(ArtifactRecordStore.self) private var artifactRecordStore
    @Environment(SkillStore.self) private var skillStore

    // MARK: - State

    @State private var coordinator: StandaloneKCCoordinator?
    @State private var sources: [URL] = []
    @State private var showFileImporter = false
    @State private var showExistingArtifactsPicker = false
    /// Artifact IDs that have been added from archived artifacts (for display)
    @State private var addedArchivedArtifactIds: Set<String> = []
    /// Analysis result for multi-card generation
    @State private var analysisResult: StandaloneKCCoordinator.AnalysisResult?
    /// Show the analysis confirmation sheet
    @State private var showAnalysisSheet = false
    /// Whether to run deduplication on narrative cards
    @State private var deduplicateNarratives = false
    /// Whether to extract and persist skills from imported documents
    @State private var extractSkillsAfterImport = true

    // MARK: - Callbacks

    var onCardGenerated: ((KnowledgeCard) -> Void)?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            contentSection
            Divider()
            footerSection
        }
        .frame(width: 550, height: 500)
        .onAppear {
            coordinator = StandaloneKCCoordinator(
                llmFacade: llmFacade,
                knowledgeCardStore: knowledgeCardStore,
                artifactRecordStore: artifactRecordStore,
                skillStore: skillStore
            )
        }
        .sheet(isPresented: $showExistingArtifactsPicker) {
            ExistingArtifactsPickerSheet(
                artifactRecordStore: artifactRecordStore,
                onDismiss: { showExistingArtifactsPicker = false },
                onSelect: { artifactIds in
                    addedArchivedArtifactIds.formUnion(artifactIds)
                }
            )
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: supportedDocumentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
        .sheet(isPresented: $showAnalysisSheet) {
            if let result = analysisResult, let coordinator = coordinator {
                AnalysisConfirmationView(
                    result: result,
                    onConfirm: { selectedNew, selectedEnhancements in
                        Task {
                            let (created, _, _) = try await coordinator.generateSelected(
                                newCards: selectedNew,
                                enhancements: selectedEnhancements,
                                artifacts: result.artifacts,
                                skillBank: result.skillBank,
                                persistSkills: extractSkillsAfterImport
                            )
                            // Notify caller of first created card (for UI refresh)
                            if created > 0, let first = selectedNew.first {
                                onCardGenerated?(first)
                            }
                            showAnalysisSheet = false
                            try? await Task.sleep(for: .seconds(1))
                            dismiss()
                        }
                    },
                    onCancel: {
                        showAnalysisSheet = false
                    }
                )
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Generate Knowledge Card")
                    .font(.headline)
                Text("Add documents or git repos to generate a knowledge card automatically")
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
            // Add buttons
            addButtonsSection

            // Sources list
            sourcesListSection

            // Options
            optionsSection

            // Status display
            if let coordinator = coordinator, coordinator.status != .idle {
                statusSection(coordinator.status)
            }
        }
        .padding()
    }

    private var optionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Deduplicate Narratives", isOn: $deduplicateNarratives)
                    .help("Run LLM-powered deduplication to merge similar narrative cards")
                Toggle("Extract skills from documents", isOn: $extractSkillsAfterImport)
                    .help("Extract and add skills to the Skill Bank from imported documents")
            }
        }
    }

    private var archivedArtifactCount: Int {
        artifactRecordStore.archivedArtifacts.count
    }

    private var addButtonsSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: { showFileImporter = true }) {
                    Label("Add Documents", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(coordinator?.status.isProcessing == true)

                Button(action: selectGitRepo) {
                    Label("Add Git Repo", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(coordinator?.status.isProcessing == true)

                // Use Existing button (only show if there are archived artifacts)
                if archivedArtifactCount > 0 {
                    Button(action: { showExistingArtifactsPicker = true }) {
                        Label("Use Existing (\(archivedArtifactCount))", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .disabled(coordinator?.status.isProcessing == true)
                }

                Spacer()

                if !sources.isEmpty || !addedArchivedArtifactIds.isEmpty {
                    Button(action: {
                        sources.removeAll()
                        addedArchivedArtifactIds.removeAll()
                    }) {
                        Text("Clear All")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(coordinator?.status.isProcessing == true)
                }
            }

            // Show added archived artifacts info
            if !addedArchivedArtifactIds.isEmpty {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                    Text("\(addedArchivedArtifactIds.count) existing artifact\(addedArchivedArtifactIds.count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var hasAnySources: Bool {
        !sources.isEmpty || !addedArchivedArtifactIds.isEmpty
    }

    private var sourcesListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sources.isEmpty && addedArchivedArtifactIds.isEmpty {
                emptyStateView
            } else {
                Text("Sources (\(sources.count)):")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(sources, id: \.absoluteString) { url in
                            sourceRowView(url)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No sources added")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Add PDF, DOCX, or TXT files, or select a git repository folder")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sourceRowView(_ url: URL) -> some View {
        HStack {
            Image(systemName: isGitRepository(url) ? "folder.fill" : documentIcon(for: url))
                .foregroundStyle(isGitRepository(url) ? .orange : .blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(isGitRepository(url) ? "Git Repository" : url.pathExtension.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { removeSource(url) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(coordinator?.status.isProcessing == true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func statusSection(_ status: StandaloneKCCoordinator.Status) -> some View {
        HStack(spacing: 12) {
            if status.isProcessing {
                ProgressView()
                    .controlSize(.small)
            } else if case .completed = status {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if case .failed = status {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }

            Text(status.displayText)
                .font(.subheadline)
                .foregroundStyle(statusColor(status))

            Spacer()
        }
        .padding()
        .background(statusBackground(status))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusColor(_ status: StandaloneKCCoordinator.Status) -> Color {
        switch status {
        case .failed: return .red
        case .completed: return .green
        default: return .primary
        }
    }

    private func statusBackground(_ status: StandaloneKCCoordinator.Status) -> Color {
        switch status {
        case .failed: return .red.opacity(0.1)
        case .completed: return .green.opacity(0.1)
        default: return .blue.opacity(0.1)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if let coordinator = coordinator, case .failed(let error) = coordinator.status {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Analyze") {
                analyzeDocuments()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasAnySources || coordinator?.status.isProcessing == true)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Helpers

    private var supportedDocumentTypes: [UTType] {
        [.pdf, .plainText, UTType(filenameExtension: "docx") ?? .data, .rtf, .html]
    }

    private func documentIcon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.richtext.fill"
        case "docx", "doc": return "doc.fill"
        case "txt": return "doc.text.fill"
        default: return "doc.fill"
        }
    }

    private func isGitRepository(_ url: URL) -> Bool {
        let gitDir = url.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                if !sources.contains(where: { $0.absoluteString == url.absoluteString }) {
                    sources.append(url)
                }
            }
        case .failure(let error):
            Logger.error("❌ DocumentIngestionSheet: File selection failed - \(error.localizedDescription)", category: .ai)
        }
    }

    private func selectGitRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a Git repository folder"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            if isGitRepository(url) {
                if !sources.contains(where: { $0.absoluteString == url.absoluteString }) {
                    sources.append(url)
                }
            } else {
                // Show error - not a git repo
                Logger.warning("⚠️ DocumentIngestionSheet: Selected folder is not a git repository", category: .ai)
            }
        }
    }

    private func removeSource(_ url: URL) {
        sources.removeAll { $0.absoluteString == url.absoluteString }
    }

    private func analyzeDocuments() {
        guard let coordinator = coordinator else { return }

        Task {
            do {
                analysisResult = try await coordinator.analyzeDocuments(
                    from: sources,
                    existingArtifactIds: addedArchivedArtifactIds,
                    deduplicateNarratives: deduplicateNarratives
                )
                showAnalysisSheet = true
            } catch {
                // Error is displayed in status section
            }
        }
    }
}

// MARK: - Existing Artifacts Picker Sheet

/// Sheet for selecting archived artifacts to use in KC generation
private struct ExistingArtifactsPickerSheet: View {
    let artifactRecordStore: ArtifactRecordStore
    let onDismiss: () -> Void
    let onSelect: (Set<String>) -> Void

    @State private var selectedIds: Set<String> = []

    private var archivedArtifacts: [ArtifactRecord] {
        artifactRecordStore.archivedArtifacts
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Previously Imported Documents")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Artifact list
            if archivedArtifacts.isEmpty {
                ContentUnavailableView(
                    "No Archived Documents",
                    systemImage: "doc.text",
                    description: Text("Previously imported documents will appear here after using the onboarding interview.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(archivedArtifacts, id: \.id) { artifact in
                            ExistingArtifactRow(
                                artifact: artifact,
                                isSelected: selectedIds.contains(artifact.id.uuidString),
                                onToggle: {
                                    let idString = artifact.id.uuidString
                                    if selectedIds.contains(idString) {
                                        selectedIds.remove(idString)
                                    } else {
                                        selectedIds.insert(idString)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(selectedIds.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Add Selected") {
                    onSelect(selectedIds)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIds.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}

private struct ExistingArtifactRow: View {
    let artifact: ArtifactRecord
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)

                fileIcon
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.filename)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Text(artifact.sourceType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var fileIcon: some View {
        let iconName: String
        let iconColor: Color

        switch artifact.sourceType {
        case "git_repository":
            iconName = "chevron.left.forwardslash.chevron.right"
            iconColor = .orange
        default:
            iconName = "doc"
            iconColor = .blue
        }

        return Image(systemName: iconName)
            .font(.body)
            .foregroundStyle(iconColor)
    }
}
