//
//  DocumentCollectionView.swift
//  Sprung
//
//  Phase 2 document collection UI: Shows proposed knowledge cards, large dropzone,
//  and "Assess Completeness" button to trigger LLM evaluation.
//
import SwiftUI
import UniformTypeIdentifiers

/// Document collection view for Phase 2 evidence gathering.
/// Combines: KC plan list + large dropzone + action button
struct DocumentCollectionView: View {
    let coordinator: OnboardingInterviewCoordinator
    let onAssessCompleteness: () -> Void
    let onDropFiles: ([URL], LargePDFExtractionMethod?) -> Void
    let onSelectFiles: () -> Void
    let onSelectGitRepo: (URL) -> Void

    @State private var isDropTargeted = false
    @State private var showGitRepoPicker = false

    private var planItems: [KnowledgeCardPlanItem] {
        coordinator.ui.knowledgeCardPlan
    }

    private var artifactCount: Int {
        coordinator.ui.artifactRecords.count
    }

    private var isCollectionActive: Bool {
        coordinator.ui.isDocumentCollectionActive
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // Main content: KC list + dropzone
            ScrollView {
                VStack(spacing: 16) {
                    // Knowledge Card Plan
                    if !planItems.isEmpty {
                        knowledgeCardPlanSection
                    }

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

    // MARK: - Knowledge Card Plan

    private var knowledgeCardPlanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Planned Knowledge Cards")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(planItems.count) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                ForEach(planItems) { item in
                    DocumentCollectionCardRow(item: item)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
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
                    }
                }
                .padding(24)
            }
            .frame(minHeight: 180)
            .onDrop(of: DropZoneHandler.acceptedDropTypes, isTargeted: $isDropTargeted) { providers in
                DropZoneHandler.handleDrop(providers: providers) { urls in
                    guard !urls.isEmpty else { return }
                    onDropFiles(urls, nil)
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
        .padding(12)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(spacing: 8) {
            Button(action: onAssessCompleteness) {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                    Text("Assess Document Completeness")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            Text("Click when done uploading to have the AI evaluate your documents")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Card Row

private struct DocumentCollectionCardRow: View {
    let item: KnowledgeCardPlanItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.type == .job ? "briefcase.fill" : "star.fill")
                .font(.caption)
                .foregroundStyle(item.type == .job ? .blue : .purple)
                .frame(width: 20)

            Text(item.title)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text(item.type == .job ? "Job" : "Skill")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(item.type == .job ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
                .foregroundStyle(item.type == .job ? .blue : .purple)
                .cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(4)
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
