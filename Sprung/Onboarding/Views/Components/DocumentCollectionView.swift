//
//  DocumentCollectionView.swift
//  Sprung
//
//  Phase 2 document collection UI: Shows proposed knowledge cards, large dropzone,
//  and "Assess Completeness" button to trigger LLM evaluation.
//
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Document collection view for Phase 2 evidence gathering.
/// Combines: KC plan list + large dropzone + action button
struct DocumentCollectionView: View {
    let coordinator: OnboardingInterviewCoordinator
    let onAssessCompleteness: () -> Void
    let onCancelExtractionsAndFinish: () -> Void
    let onDropFiles: ([URL]) -> Void
    let onSelectFiles: () -> Void
    let onSelectGitRepo: (URL) -> Void
    let onFetchURL: (String) async -> Void

    /// Current session artifacts (have a session relationship)
    @Query(filter: #Predicate<ArtifactRecord> { $0.session != nil },
           sort: \ArtifactRecord.ingestedAt)
    private var artifacts: [ArtifactRecord]

    /// Archived artifacts (no session, available for reuse)
    @Query(filter: #Predicate<ArtifactRecord> { $0.session == nil },
           sort: \ArtifactRecord.ingestedAt, order: .reverse)
    private var archivedArtifacts: [ArtifactRecord]

    @State private var isDropTargeted = false
    @State private var showGitRepoPicker = false
    @State private var showActiveAgentsAlert = false
    @State private var showArchivedArtifactsPicker = false
    @State private var showURLEntry = false

    /// Check if extraction agents are still working
    private var hasActiveExtractionAgents: Bool {
        coordinator.ui.hasBatchUploadInProgress ||
        coordinator.ui.isExtractionInProgress ||
        coordinator.ui.pendingExtraction != nil
    }

    /// Whether buttons should be disabled (during LLM processing)
    private var buttonsDisabled: Bool {
        coordinator.ui.isProcessing
    }

    private var artifactCount: Int {
        artifacts.count
    }

    private var artifactsMissingKnowledge: Int {
        artifacts.filter { !$0.extractedContent.isEmpty && !$0.hasKnowledgeExtraction }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // Main content: dropzone + artifact summary
            ScrollView {
                VStack(spacing: 16) {
                    // Large dropzone
                    dropzoneSection

                    // Uploaded artifacts summary
                    if artifactCount > 0 {
                        artifactSummarySection
                    }
                }
                .padding(16)
            }

            Divider()

            // Action buttons
            actionSection
                .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .fileImporter(
            isPresented: $showGitRepoPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                onSelectGitRepo(url)
            }
        }
        .sheet(isPresented: $showArchivedArtifactsPicker) {
            ArchivedArtifactsPickerSheet(
                coordinator: coordinator,
                onDismiss: { showArchivedArtifactsPicker = false }
            )
        }
        .sheet(isPresented: $showURLEntry) {
            URLEntrySheet(
                onSubmit: { url in
                    Task {
                        await onFetchURL(url)
                    }
                },
                onDismiss: { showURLEntry = false }
            )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Document Collection")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            Text("Upload documents to support your knowledge cards. Each file becomes a separate artifact.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Dropzone

    private var dropzoneSection: some View {
        VStack(spacing: 12) {
            // Main dropzone
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.1) : Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                                style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                            )
                    )

                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(isDropTargeted ? .blue : .secondary)

                    VStack(spacing: 4) {
                        Text("Drop files here")
                            .font(.headline)
                            .foregroundStyle(isDropTargeted ? .blue : .primary)
                        Text("PDFs, Word docs, text files, images")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button("Browse Files") {
                            onSelectFiles()
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showGitRepoPicker = true
                        } label: {
                            Label("Add Git Repo", systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showURLEntry = true
                        } label: {
                            Label("Add URL", systemImage: "link")
                        }
                        .buttonStyle(.bordered)
                    }

                    // Previously imported docs button (only show if there are archived artifacts)
                    if !archivedArtifacts.isEmpty {
                        Button {
                            showArchivedArtifactsPicker = true
                        } label: {
                            Label("Use Previously Imported (\(archivedArtifacts.count))", systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }
                }
                .padding(24)
            }
            .frame(minHeight: 180)
            .onDrop(of: DropZoneHandler.acceptedDropTypes, isTargeted: $isDropTargeted) { providers in
                DropZoneHandler.handleDrop(providers: providers) { urls in
                    guard !urls.isEmpty else { return }
                    onDropFiles(urls)
                }
                return true
            }

            // Document type suggestions
            documentSuggestionsSection
        }
    }

    private var documentSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested document types:")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(suggestedDocTypes, id: \.self) { docType in
                    Text(docType)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }

    private var suggestedDocTypes: [String] {
        [
            "Performance reviews",
            "Job descriptions",
            "Project docs",
            "Design specs",
            "Code repos",
            "Promotion emails",
            "Award certificates",
            "LinkedIn recommendations"
        ]
    }

    // MARK: - Artifact Summary

    private var artifactSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundStyle(.green)
                Text("\(artifactCount) document\(artifactCount == 1 ? "" : "s") uploaded")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("View in Artifacts tab")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Warning for artifacts missing knowledge extraction
            if artifactsMissingKnowledge > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("\(artifactsMissingKnowledge) artifact\(artifactsMissingKnowledge == 1 ? "" : "s") not yet processed for knowledge extraction")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(12)
        .background(artifactsMissingKnowledge > 0 ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(spacing: 8) {
            Button {
                if hasActiveExtractionAgents {
                    showActiveAgentsAlert = true
                } else {
                    onAssessCompleteness()
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Done with Uploads")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(buttonsDisabled)
            .alert(
                "Extraction in Progress",
                isPresented: $showActiveAgentsAlert
            ) {
                Button("OK", role: .cancel) { }
                Button("Cancel Agents and Finish", role: .destructive) {
                    onCancelExtractionsAndFinish()
                }
            } message: {
                Text("Document extraction agents are still working. You can wait for them to finish, or cancel them and proceed.")
            }

            Text("Click when finished to proceed with knowledge card generation")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, containerWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, containerWidth: bounds.width).offsets

        for (subview, offset) in zip(subviews, offsets) {
            subview.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(sizes: [CGSize], containerWidth: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX)
        }

        return (offsets, CGSize(width: maxWidth, height: currentY + lineHeight))
    }
}

// MARK: - Archived Artifacts Picker Sheet

/// Sheet for selecting archived artifacts to promote to the current interview
struct ArchivedArtifactsPickerSheet: View {
    let coordinator: OnboardingInterviewCoordinator
    let onDismiss: () -> Void

    /// Archived artifacts (no session, available for reuse)
    @Query(filter: #Predicate<ArtifactRecord> { $0.session == nil },
           sort: \ArtifactRecord.ingestedAt, order: .reverse)
    private var archivedArtifacts: [ArtifactRecord]

    @State private var selectedIds: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Previously Imported Documents")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Artifact list with checkboxes
            if archivedArtifacts.isEmpty {
                ContentUnavailableView(
                    "No Archived Documents",
                    systemImage: "doc.text",
                    description: Text("Previously imported documents will appear here.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(archivedArtifacts) { artifact in
                            ArchivedArtifactPickerRow(
                                artifact: artifact,
                                isSelected: selectedIds.contains(artifact.id),
                                onToggle: {
                                    if selectedIds.contains(artifact.id) {
                                        selectedIds.remove(artifact.id)
                                    } else {
                                        selectedIds.insert(artifact.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Footer with action button
            HStack {
                Text("\(selectedIds.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Add to Interview") {
                    Task {
                        // Use batch promotion for proper LLM notification batching
                        let ids = selectedIds.map { $0.uuidString }
                        await coordinator.promoteArchivedArtifacts(ids: ids)
                        onDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIds.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}

private struct ArchivedArtifactPickerRow: View {
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
                    Text(artifact.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    if let brief = artifact.briefDescription, !brief.isEmpty {
                        Text(brief)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(artifact.filename)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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

        switch artifact.contentType?.lowercased() {
        case let type where type?.contains("pdf") == true:
            iconName = "doc.richtext"
            iconColor = .red
        case let type where type?.contains("word") == true || type?.contains("docx") == true:
            iconName = "doc.text"
            iconColor = .blue
        case let type where type?.contains("image") == true:
            iconName = "photo"
            iconColor = .green
        default:
            if artifact.sourceType == "git_repository" {
                iconName = "chevron.left.forwardslash.chevron.right"
                iconColor = .orange
            } else {
                iconName = "doc"
                iconColor = .gray
            }
        }

        return Image(systemName: iconName)
            .font(.body)
            .foregroundStyle(iconColor)
    }
}

// MARK: - URL Entry Sheet

/// Sheet for entering a URL to fetch and create an artifact from
struct URLEntrySheet: View {
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    @State private var urlString: String = ""
    @State private var errorMessage: String?
    @FocusState private var isURLFieldFocused: Bool

    private var isValidURL: Bool {
        guard !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow URLs with or without scheme - we'll normalize later
        let urlWithScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        return URL(string: urlWithScheme) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.blue)
                Text("Add URL")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // URL entry
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter a URL to fetch and add as an artifact:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("https://example.com/portfolio", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .focused($isURLFieldFocused)
                    .onSubmit {
                        if isValidURL {
                            submitURL()
                        }
                    }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("The agent will visit this URL and extract relevant content to create an artifact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Spacer()

            Divider()

            // Footer
            HStack {
                Text("Supported: Portfolio sites, LinkedIn profiles, GitHub, company pages, articles")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Fetch URL") {
                    submitURL()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValidURL)
            }
            .padding()
        }
        .frame(width: 450, height: 250)
        .onAppear {
            isURLFieldFocused = true
        }
    }

    private func submitURL() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Normalize URL (add https:// if missing)
        let normalizedURL = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"

        guard URL(string: normalizedURL) != nil else {
            errorMessage = "Please enter a valid URL"
            return
        }

        onSubmit(normalizedURL)
        onDismiss()
    }
}
